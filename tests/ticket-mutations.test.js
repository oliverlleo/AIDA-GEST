const test = require('node:test');
const assert = require('node:assert/strict');
global.window = global;
require('../js/modules/ticket-mutations.js');
require('../js/modules/workflow-rules.js');

function fixture() {
    const calls = [], events = [];
    const deps = {
        canExecuteAction: (ticket, action) => global.AIDAWorkflowRules.canExecuteAction(ticket, action, role => role === 'tester', { test_flow: 'tester' }),
        supabaseFetch: async (endpoint, method, payload) => { calls.push({ endpoint, method, payload }); return { success: true, ticket_id: payload.p_ticket_id, status: payload.p_status }; },
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
        const ticket = { id: 'ticket-id', status: 'Teste Final', test_start_at: '2026-10-14T12:00:00Z' };
        const checklist = [{ item: 'Tela', ok: true }];
        const result = await global.AIDATicketMutations.updateStatus(ticket, status,
            { checklist_final_data: checklist, status, updated_at: 'nao-usar-timestamp-do-cliente' },
            { action: 'Texto do cliente', details: 'Nao deve ser enviado ao log' }, deps);
        assert.equal(result, true);
        assert.deepEqual(calls, [{ endpoint: 'rpc/conclude_ticket_test', method: 'POST', payload: {
            p_ticket_id: ticket.id, p_status: status, p_updates: { checklist_final_data: checklist }
        } }]);
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
    const ticket = { id: 'ticket-id', status: 'Teste Final', test_start_at: '2026-10-14T12:00:00Z' };
    const result = await global.AIDATicketMutations.updateStatus(ticket, 'Retirada Cliente', { budget_status: 'Aprovado' }, { action: 'Nao gravar' }, deps);
    assert.equal(result, false);
    assert.equal(calls[0].endpoint, 'rpc/conclude_ticket_test');
    assert.deepEqual(calls[0].payload.p_updates, { budget_status: 'Aprovado' });
    assert.equal(events.some(event => ['selected', 'clientLog', 'refresh', 'close'].includes(event.kind)), false);
    assert.equal(events.find(event => event.kind === 'notice').type, 'error');
    assert.equal(events.at(-1).value, false);
});

test('edicao normal continua PATCH e preserva log, refresh e retorno vazio', async () => {
    const { deps, calls, events } = fixture();
    deps.canExecuteAction = () => true;
    deps.supabaseFetch = async (endpoint, method, payload) => { calls.push({ endpoint, method, payload }); return null; };
    const ticket = { id: 'ticket-id', status: 'Andamento Reparo' };
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
