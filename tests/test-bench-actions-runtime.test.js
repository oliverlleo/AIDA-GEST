const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.join(__dirname, '..');
const copy = value => JSON.parse(JSON.stringify(value));

function runtime({ roles = ['tester'], ticket = {} } = {}) {
    let server = {
        id: 'test-os', workspace_id: 'company-a', revision: 4, status: 'Teste Final',
        test_start_at: '2026-10-16T12:00:00Z', technician_id: 'technician-a',
        device_model: 'Aparelho', client_name: 'Cliente', os_number: '123',
        priority: 'Normal', checklist_final_data: [{ item: 'Imagem', ok: false }],
        ...ticket
    };
    const calls = [], events = [], messages = [];
    const sandbox = {
        Date, URL, TextEncoder, setTimeout, clearTimeout, setInterval, clearInterval,
        console: { log() {}, warn() {}, error() {} }, addEventListener() {},
        document: { addEventListener() {}, visibilityState: 'visible' },
        SUPABASE_CONFIG: { URL: 'https://example.supabase.co', KEY: 'public-test-key' },
        supabase: { createClient: () => ({}) }
    };
    sandbox.window = sandbox;
    const context = vm.createContext(sandbox);
    for (const file of ['js/modules/feature-config.js', 'js/modules/config-helpers.js',
        'js/modules/ticket-context.js', 'js/modules/customer-service.js', 'js/modules/inventory-catalog-service.js',
        'js/modules/workflow-rules.js', 'js/modules/workspace-sync-service.js', 'js/modules/ticket-query-service.js',
        'js/modules/ticket-mutations.js', 'js/modules/ticket-actions.js', 'js/main.js']) {
        vm.runInContext(fs.readFileSync(path.join(root, file), 'utf8'), context, { filename: file });
    }
    const state = vm.runInContext('app()', context);
    state.user = { id: 'tester-a', employee_id: 'tester-a', workspace_id: 'company-a', roles, name: 'Qualidade' };
    state.session = { user: { id: 'account-a' }, access_token: 'synthetic-jwt' };
    state.view = 'tester_bench';
    state.trackerConfig.test_flow = 'tester';
    const card = () => {
        const result = { ...copy(server), _card_summary: true };
        delete result.checklist_final_data;
        return result;
    };
    state.tickets = [card()];
    state.notify = (message, type) => messages.push({ message, type });
    state.isFieldRequired = () => false;
    state.isAppointmentTypeEnabled = () => true;
    state.openSchedulePanel = () => events.push('schedule');
    state.fetchTickets = async () => { events.push('refresh'); state.tickets = server.status === 'Teste Final' ? [card()] : []; };
    state.fetchGlobalLogs = async () => {};
    state.logTicketAction = async () => events.push('log');
    state.supabaseFetch = async (endpoint, method = 'GET', payload, options) => {
        calls.push({ endpoint, method, payload: payload && copy(payload), options: options && copy(options) });
        if (method === 'GET') return [copy(server)];
        if (Number(options?.ticketVersion?.revision) !== server.revision) {
            throw Object.assign(new Error('Snapshot desatualizado'), { status: 409, code: 'PT409' });
        }
        if (method === 'PATCH') {
            server = { ...server, ...payload, revision: server.revision + 1 };
            return [copy(server)];
        }
        if (endpoint === 'rpc/conclude_ticket_test') {
            server = { ...server, ...payload.p_updates, status: payload.p_status, revision: server.revision + 1 };
            return { success: true, ticket_id: server.id, status: server.status };
        }
        throw new Error('Unexpected endpoint ' + endpoint);
    };
    return { state, context, calls, events, messages, server: () => server };
}

test('card starts the test through existing CAS without opening either modal', async () => {
    const r = runtime({ ticket: { test_start_at: null } });
    await r.state.startTest(r.state.tickets[0]);
    assert.equal(r.calls.length, 1);
    assert.equal(r.calls[0].method, 'PATCH');
    assert.equal(r.calls[0].options.ticketVersion.revision, '4');
    assert.ok(r.server().test_start_at);
    assert.equal(r.state.modals.outcome, false);
    assert.equal(r.state.modals.viewTicket, false);
});

test('approval card opens only the small dialog with the full authorized checklist', async () => {
    const r = runtime();
    r.state.selectedTicket = { id: 'old-os', revision: 900, checklist_final_data: [] };
    r.state.testFailureData.reason = 'Motivo de outra OS';
    assert.equal(await r.state.openOutcomeModal('test', r.state.tickets[0], 'approve'), true);
    assert.equal(r.calls.length, 1);
    assert.match(r.calls[0].endpoint, /^tickets\?select=\*&id=eq\.test-os&workspace_id=eq\.company-a&limit=1$/);
    assert.equal(r.state.selectedTicket.revision, 4);
    assert.equal(r.state.selectedTicket.checklist_final_data[0].item, 'Imagem');
    assert.equal(r.state.outcomeDecision, 'approve');
    assert.equal(r.state.showTestFailureForm, false);
    assert.equal(r.state.testFailureData.reason, '');
    assert.equal(r.state.modals.outcome, true);
    assert.equal(r.state.modals.viewTicket, false);
});

test('approval checks the checklist, sends only allowed fields and keeps CAS revision', async () => {
    const r = runtime();
    await r.state.openOutcomeModal('test', r.state.tickets[0], 'approve');
    assert.deepEqual(copy(r.state.getFinalTestChecklistProgress()), { total: 1, checked: 0, pending: 1 });
    assert.equal(await r.state.concludeTest(true), false);
    assert.equal(r.calls.length, 1);
    r.state.selectedTicket.checklist_final_data[0].ok = true;
    assert.equal(await r.state.concludeTest(true), true);
    const write = r.calls.find(call => call.method === 'POST');
    assert.equal(write.endpoint, 'rpc/conclude_ticket_test');
    assert.equal(write.options.ticketVersion.revision, '4');
    assert.deepEqual(Object.keys(write.payload.p_updates), ['checklist_final_data']);
    assert.equal(write.payload.p_updates.checklist_final_data[0].ok, true);
    assert.equal(r.state.modals.outcome, false);
    assert.equal(r.state.modals.viewTicket, false);
    assert.equal(r.server().status, 'Retirada Cliente');
});

test('empty optional checklist is accepted while an explicitly required checklist is enforced', async () => {
    for (const required of [false, true]) {
        const r = runtime({ ticket: { checklist_final_data: [] } });
        r.state.isFieldRequired = () => required;
        await r.state.openOutcomeModal('test', r.state.tickets[0], 'approve');
        assert.equal(await r.state.concludeTest(true), !required);
        assert.equal(r.calls.some(call => call.method === 'POST'), !required);
    }
});

test('rejection requires a real reason and retains failed checklist items without offering forbidden scheduling', async () => {
    const r = runtime();
    await r.state.openOutcomeModal('test', r.state.tickets[0], 'reject');
    assert.equal(r.state.outcomeDecision, 'reject');
    assert.equal(r.state.showTestFailureForm, true);
    r.state.testFailureData.reason = '   ';
    assert.equal(await r.state.concludeTest(false), false);
    assert.equal(r.calls.length, 1);
    r.state.testFailureData.reason = 'Imagem falhando';
    r.state.testFailureData.newDeadline = '2026-10-20T12:00';
    assert.equal(await r.state.concludeTest(false), true);
    const write = r.calls.find(call => call.method === 'POST');
    assert.equal(write.payload.p_status, 'Andamento Reparo');
    assert.equal(write.payload.p_updates.checklist_final_data[0].ok, false);
    assert.equal(write.payload.p_updates.test_notes[0].text, 'Imagem falhando');
    assert.ok(!r.events.includes('schedule'));
    assert.equal(r.state.modals.outcome, false);
});

test('outsourced rejection still requires its destination and deadline', async () => {
    const r = runtime({ ticket: { is_outsourced: true, outsourced_company_id: 'company-b' } });
    await r.state.openOutcomeModal('test', r.state.tickets[0], 'reject');
    r.state.testFailureData.reason = 'Defeito persiste';
    await r.state.concludeTest(false);
    assert.equal(r.calls.length, 1);
    assert.equal(r.state.modals.outcome, true);
    r.state.testFailureData.action = 'return';
    r.state.testFailureData.newDeadline = '2026-10-20T12:00';
    assert.equal(await r.state.concludeTest(false), true);
    assert.equal(r.calls.find(call => call.method === 'POST').payload.p_status, 'Terceirizado');
});

test('legitimate schedule access remains available after rejection for managers and the responsible technician', async () => {
    for (const [roles, employeeId, expected] of [
        [['admin'], 'manager-a', true], [['tester', 'atendente'], 'attendant-a', true],
        [['tester', 'tecnico'], 'technician-a', true], [['tester', 'tecnico'], 'other-technician', false]
    ]) {
        const r = runtime({ roles });
        r.state.user.id = r.state.user.employee_id = employeeId;
        await r.state.openOutcomeModal('test', r.state.tickets[0], 'reject');
        r.state.testFailureData.reason = 'Falha de imagem';
        r.state.testFailureData.newDeadline = '2026-10-20T12:00';
        assert.equal(await r.state.concludeTest(false), true);
        assert.equal(r.events.includes('schedule'), expected);
    }
});

test('a concurrent change keeps the checked draft open and never announces approval', async () => {
    const r = runtime();
    await r.state.openOutcomeModal('test', r.state.tickets[0], 'approve');
    r.state.selectedTicket.checklist_final_data[0].ok = true;
    r.server().revision = 5;
    assert.equal(await r.state.concludeTest(true), false);
    assert.equal(r.state.modals.outcome, true);
    assert.equal(r.state.selectedTicket.revision, 4);
    assert.equal(r.state.selectedTicket.checklist_final_data[0].ok, true);
    assert.equal(r.server().status, 'Teste Final');
    assert.equal(r.calls.filter(call => call.method === 'POST').length, 1);
});

test('full OS drafts keep their original version and checklist when opening the compact result dialog', async () => {
    const r = runtime();
    r.state.modals.viewTicket = true;
    r.state.selectedTicket = { ...copy(r.server()), revision: 3, checklist_final_data: [{ item: 'Imagem', ok: true }] };
    r.context.AIDAWorkspaceSyncService.captureTicket(r.state, { ...copy(r.server()), revision: 3 });
    assert.equal(await r.state.openOutcomeModal('test', r.state.selectedTicket, 'approve'), true);
    assert.equal(r.calls.length, 0);
    assert.equal(r.state.selectedTicket.revision, 3);
    assert.equal(r.state.selectedTicket.checklist_final_data[0].ok, true);
    assert.equal(await r.state.concludeTest(true), false);
    assert.equal(r.state.modals.outcome, true);
    assert.equal(r.state.selectedTicket.checklist_final_data[0].ok, true);
});

test('current phase, test start and role are rechecked after loading before showing actions', async () => {
    for (const options of [{ roles: ['atendente'] }, { ticket: { test_start_at: null } },
        { ticket: { status: 'Retirada Cliente' } }, { ticket: { deleted_at: '2026-10-16' } }]) {
        const r = runtime(options);
        assert.equal(await r.state.openOutcomeModal('test', r.state.tickets[0], 'approve'), false);
        assert.equal(r.state.modals.outcome, false);
        assert.ok(!r.calls.some(call => call.method !== 'GET'));
    }
});

test('changing the screen while details load discards the response instead of opening an old dialog', async () => {
    const r = runtime();
    let release;
    r.state.supabaseFetch = async () => new Promise(resolve => { release = resolve; });
    const opening = r.state.openOutcomeModal('test', r.state.tickets[0], 'approve');
    r.state.view = 'kanban';
    release([copy(r.server())]);
    assert.equal(await opening, false);
    assert.equal(r.state.modals.outcome, false);
    assert.equal(r.state.selectedTicket, null);
    assert.equal(r.state.loading, false);
});
