const test = require('node:test');
const assert = require('node:assert/strict');
global.window = global;
require('../js/modules/ticket-mutations.js');
require('../js/modules/workflow-rules.js');

function fixture() {
    const calls = [], events = [];
    const deps = {
        canExecuteAction: (ticket, action) => global.AIDAWorkflowRules.canExecuteAction(ticket, action, role => role === 'tester', { test_flow: 'tester' }),
        supabaseFetch: async (endpoint, method, payload, options) => { calls.push({ endpoint, method, payload, options }); return { success: true, ticket_id: payload.p_ticket_id, status: payload.p_status }; },
        setLoading: value => events.push({ kind: 'loading', value }),
        updateSelectedTicket: (id, updates) => events.push({ kind: 'selected', id, updates }),
        logTicketAction: async () => events.push({ kind: 'clientLog' }),
        notify: (message, type) => events.push({ kind: 'notice', message, type }),
        fetchTickets: async () => events.push({ kind: 'refresh' }),
        closeViewModal: () => events.push({ kind: 'close' })
    };
    return { deps, calls, events };
}

test('tester conclui os tres destinos por RPC sem PATCH nem log duplicado do cliente', async () => {
    for (const status of ['Retirada Cliente', 'Andamento Reparo', 'Terceirizado']) {
        const { deps, calls, events } = fixture();
        const ticket = { id: 'ticket-id', revision: 4, status: 'Teste Final', test_start_at: '2026-10-14T12:00:00Z' };
        const checklist = [{ item: 'Tela', ok: true }];
        const result = await global.AIDATicketMutations.updateStatus(ticket, status,
            { checklist_final_data: checklist, status, updated_at: 'nao-usar-timestamp-do-cliente' },
            { action: 'Texto do cliente', details: 'Nao deve ser enviado ao log' }, deps);
        assert.equal(result, true);
        assert.deepEqual(calls, [{ endpoint: 'rpc/conclude_ticket_test', method: 'POST', payload: {
            p_ticket_id: ticket.id, p_status: status, p_updates: { checklist_final_data: checklist }
        }, options: { ticketVersion: { id: ticket.id, revision: '4' } } }]);
        assert.equal(events.some(event => event.kind === 'clientLog'), false);
        const selected = events.find(event => event.kind === 'selected');
        assert.equal(selected.updates.status, status);
        assert.deepEqual(selected.updates.checklist_final_data, checklist);
        assert.notEqual(selected.updates.updated_at, 'nao-usar-timestamp-do-cliente');
        assert.equal(events.some(event => event.kind === 'refresh'), true);
        assert.equal(events.some(event => event.kind === 'close'), true);
        assert.equal(events.at(-1).value, false);
    }
});

test('rejeicao da whitelist no servidor interrompe resultado local e log/refresh', async () => {
    const { deps, calls, events } = fixture();
    deps.supabaseFetch = async (endpoint, method, payload) => {
        calls.push({ endpoint, method, payload });
        throw Object.assign(new Error('Campo nao permitido para concluir teste.'), { status: 403, code: '42501' });
    };
    const ticket = { id: 'ticket-id', revision: 4, status: 'Teste Final', test_start_at: '2026-10-14T12:00:00Z' };
    const result = await global.AIDATicketMutations.updateStatus(ticket, 'Retirada Cliente', { budget_status: 'Aprovado' }, { action: 'Nao gravar' }, deps);
    assert.equal(result, false);
    assert.equal(calls[0].endpoint, 'rpc/conclude_ticket_test');
    assert.deepEqual(calls[0].payload.p_updates, { budget_status: 'Aprovado' });
    assert.equal(events.some(event => ['selected', 'clientLog', 'refresh', 'close'].includes(event.kind)), false);
    assert.equal(events.find(event => event.kind === 'notice').type, 'error');
    assert.equal(events.at(-1).value, false);
});

test('edicao normal continua PATCH e preserva log e refresh após confirmação', async () => {
    const { deps, calls, events } = fixture();
    deps.canExecuteAction = () => true;
    deps.supabaseFetch = async (endpoint, method, payload) => { calls.push({ endpoint, method, payload }); return [{ id: 'ticket-id', revision: 5, ...payload }]; };
    const ticket = { id: 'ticket-id', revision: 4, status: 'Andamento Reparo' };
    const result = await global.AIDATicketMutations.mutateTicket(ticket, 'saveTicketChanges', { tech_notes: 'Diagnostico' },
        { action: 'Salvou anotacoes', details: 'Detalhe' }, { closeViewModal: true }, deps);
    assert.equal(result, true);
    assert.equal(calls[0].endpoint, 'tickets?id=eq.ticket-id');
    assert.equal(calls[0].method, 'PATCH');
    assert.equal(calls[0].payload.tech_notes, 'Diagnostico');
    assert.equal(events.some(event => event.kind === 'clientLog'), true);
    assert.equal(events.some(event => event.kind === 'selected'), true);
    assert.equal(events.some(event => event.kind === 'refresh'), true);
    assert.equal(events.some(event => event.kind === 'close'), true);
});

test('conflito preserva formulário e não aplica, registra, fecha ou repete gravação', async () => {
    const { deps, calls, events } = fixture();
    deps.canExecuteAction = () => true;
    deps.supabaseFetch = async (endpoint, method, payload, options) => {
        calls.push({ endpoint, method, payload, options });
        throw Object.assign(new Error('conflito'), { status: 409, code: 'PT409' });
    };
    const ticket = { id: 'ticket-id', revision: 5, status: 'Analise Tecnica', tech_notes: 'rascunho' };
    assert.equal(await global.AIDATicketMutations.mutateTicket(ticket, 'saveTicketChanges',
        { tech_notes: 'rascunho' }, { action: 'salvou' }, { closeViewModal: true }, deps), false);
    assert.equal(calls.length, 1);
    assert.equal(ticket.tech_notes, 'rascunho');
    assert.equal(ticket.revision, 5);
    assert.equal(events.some(event => ['selected', 'clientLog', 'refresh', 'close'].includes(event.kind)), false);
    assert.match(events.find(event => event.kind === 'notice').message, /continuam no formulário/);
});

test('resposta PATCH confirma revisão real e informa quais campos foram enviados', async () => {
    const { deps, events } = fixture();
    deps.canExecuteAction = () => true;
    const saved = { id: 'ticket-id', revision: 12, tech_notes: 'salvo', status: 'Analise Tecnica' };
    deps.supabaseFetch = async () => [saved];
    deps.updateSelectedTicket = (id, committed, submitted) => events.push({ kind: 'confirmed', committed, submitted });
    assert.equal(await global.AIDATicketMutations.mutateTicket({ ...saved, revision: 11 }, 'saveTicketChanges',
        { tech_notes: 'salvo' }, null, {}, deps), true);
    const confirmed = events.find(event => event.kind === 'confirmed');
    assert.equal(confirmed.committed.revision, 12);
    assert.equal(confirmed.submitted.tech_notes, 'salvo');
    assert.equal('revision' in confirmed.submitted, false);
});

test('duplo clique no mesmo PC envia uma gravação enquanto a primeira aguarda', async () => {
    const { deps } = fixture();
    deps.canExecuteAction = () => true;
    let complete, calls = 0;
    deps.supabaseFetch = async () => { calls++; return new Promise(resolve => { complete = resolve; }); };
    const ticket = { id: 'ticket-id', revision: 1, status: 'Aberto' };
    const first = global.AIDATicketMutations.mutateTicket(ticket, 'saveTicketChanges', {}, null, {}, deps);
    assert.equal(await global.AIDATicketMutations.mutateTicket(ticket, 'saveTicketChanges', {}, null, {}, deps), false);
    assert.equal(calls, 1);
    complete([{ ...ticket, revision: 2 }]);
    assert.equal(await first, true);
});

test('falha de atualização depois do commit não declara falha de gravação nem repete write', async () => {
    const { deps, calls, events } = fixture();
    deps.canExecuteAction = () => true;
    deps.supabaseFetch = async (endpoint, method, payload) => { calls.push({ endpoint, method, payload }); return [{ id: 'ticket-id', revision: 2, ...payload }]; };
    deps.fetchTickets = async () => { throw new Error('offline após salvar'); };
    assert.equal(await global.AIDATicketMutations.mutateTicket({ id: 'ticket-id', revision: 1 }, 'saveTicketChanges', {}, null, {}, deps), true);
    assert.equal(calls.length, 1);
    assert.match(events.at(-2).message, /alteração foi salva/);
});

test('PATCH sem linha retornada não gera sucesso, log ou estado fictício', async () => {
    const { deps, events } = fixture();
    deps.canExecuteAction = () => true;
    deps.supabaseFetch = async () => [];
    deps.onConflict = async () => events.push({ kind: 'conflict' });
    assert.equal(await global.AIDATicketMutations.mutateTicket({ id: 'ticket-id', revision: 1 }, 'saveTicketChanges', {}, null, {}, deps), false);
    assert.equal(events.some(event => ['selected', 'clientLog', 'refresh', 'close'].includes(event.kind)), false);
    assert.equal(events.some(event => event.kind === 'conflict'), true);
});

test('mutations e API reais compartilham o contrato de versão no cabeçalho', async () => {
    require('../js/modules/api-client.js');
    const { deps } = fixture();
    deps.canExecuteAction = () => true;
    const originalFetch = global.fetch;
    let header;
    global.fetch = async (_url, request) => {
        header = JSON.parse(request.headers['x-aida-ticket-version']);
        return new Response(JSON.stringify([{ id: 'ticket-id', revision: 8, tech_notes: 'salvo' }]), { status: 200, headers: { 'Content-Type': 'application/json' } });
    };
    try {
        deps.supabaseFetch = (endpoint, method, payload, options) => global.AIDAApiClient.supabaseFetch(endpoint, method, payload,
            { SUPABASE_URL: 'https://example.invalid', SUPABASE_KEY: 'public-test', state: { session: { access_token: 'synthetic-test-token' }, user: { id: 'user-id', workspace_id: 'workspace-id' } } }, options);
        assert.equal(await global.AIDATicketMutations.mutateTicket({ id: 'ticket-id', revision: 7 }, 'saveTicketChanges', { tech_notes: 'salvo' }, null, {}, deps), true);
        assert.equal(header.id, 'ticket-id');
        assert.equal(Number(header.revision), 7);
    } finally { global.fetch = originalFetch; }
});

test('resposta de contexto antigo não altera tela nem mostra aviso na empresa nova', async () => {
    const { deps, events } = fixture();
    deps.canExecuteAction = () => true;
    deps.supabaseFetch = async () => { throw Object.assign(new Error('contexto trocado'), { contextChanged: true }); };
    assert.equal(await global.AIDATicketMutations.mutateTicket({ id: 'ticket-id', revision: 1 }, 'saveTicketChanges', {}, null, {}, deps), false);
    assert.equal(events.some(event => ['notice', 'selected', 'clientLog', 'refresh'].includes(event.kind)), false);
});
