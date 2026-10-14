const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.join(__dirname, '..');
const USER = '11111111-1111-4111-8111-111111111111';
const OWNER_WORKSPACE = '22222222-2222-4222-8222-222222222222';
const STAFF_WORKSPACE = '33333333-3333-4333-8333-333333333333';
const EMPLOYEE = '44444444-4444-4444-8444-444444444444';

function runtime(roles = ['tecnico']) {
    const storage = new Map([
        [`centralos_workspace:${USER}`, STAFF_WORKSPACE],
        ['techassist_employee', '{"token":"retired-credential","roles":["admin"]}']
    ]);
    const events = [], requests = [], timeouts = [];
    const session = { access_token: 'supabase-jwt', user: { id: USER, email: 'person@example.test' } };
    let listener;
    const client = {
        auth: { getSession: async () => ({ data: { session } }), onAuthStateChange: callback => { listener = callback; } },
        removeAllChannels: async () => events.push('channels_removed')
    };
    const sandbox = {
        console: { log() {}, warn() {}, error() {} }, Date, URL, TextEncoder,
        SUPABASE_CONFIG: { URL: 'https://example.supabase.co', KEY: 'publishable-key' },
        supabase: { createClient: (_url, _key, options) => { assert.equal(options.auth.flowType, 'pkce'); return client; } },
        document: { visibilityState: 'visible', addEventListener() {}, querySelector: () => ({}) },
        location: { href: 'https://oliverlleo.github.io/AIDA-GEST/app.html', reload: () => events.push('reload'), replace: () => events.push('replace') },
        history: { replaceState() {} }, addEventListener() {},
        localStorage: { getItem: key => storage.get(key) || null, setItem: (key, value) => storage.set(key, value), removeItem: key => storage.delete(key) },
        sessionStorage: { getItem: () => null, setItem() {}, removeItem() {} },
        setInterval: () => 1, clearTimeout() {}, setTimeout: callback => { timeouts.push(callback); return timeouts.length; },
        AIDAStorageService: { clearLocalPhotoPreviews: () => events.push('previews_cleared') }
    };
    sandbox.window = sandbox;
    const context = vm.createContext(sandbox);
    for (const file of ['js/modules/feature-config.js', 'js/modules/config-helpers.js', 'js/modules/ticket-context.js', 'js/modules/customer-service.js', 'js/modules/inventory-catalog-service.js', 'js/modules/auth-session-service.js', 'js/main.js']) {
        vm.runInContext(fs.readFileSync(path.join(root, file), 'utf8'), context, { filename: file });
    }
    const state = vm.runInContext('app()', context);
    state.$watch = () => {};
    state.normalizeFeatureConfig = () => {};
    state.supabaseFetch = async (endpoint, _method, payload) => {
        requests.push({ endpoint, payload });
        if (endpoint === 'rpc/list_my_workspaces') return [
            { workspace_id: OWNER_WORKSPACE, workspace_name: 'Minha empresa', member_kind: 'owner', roles: ['admin'] },
            { workspace_id: STAFF_WORKSPACE, workspace_name: 'Empregador', member_kind: 'employee', employee_id: EMPLOYEE, roles }
        ];
        if (endpoint === 'rpc/list_my_pending_invitations') return [];
        if (endpoint === 'rpc/get_my_access_context') return {
            workspace_id: STAFF_WORKSPACE, workspace_name: 'Empregador', auth_user_id: USER,
            employee_id: EMPLOYEE, member_kind: 'employee', name: 'Ana', roles, tracker_config: { test_flow: 'tester' }
        };
        throw new Error(`Unexpected request: ${endpoint}`);
    };
    for (const name of ['fetchEmployees', 'fetchTemplates', 'fetchDeviceModels', 'fetchDefectOptions', 'fetchOutsourcedCompanies', 'fetchFornecedores', 'fetchGlobalLogs']) {
        state[name] = async () => events.push(name);
    }
    state.fetchTickets = async () => events.push(`tickets:${state.view}`);
    return { state, context, storage, events, requests, session, client, listener: () => listener, timeouts };
}

test('bootstrap permanece ativo durante a restauração da sessão e da empresa', async () => {
    const { state, client, session } = runtime();
    let releaseSession, sessionStarted, releaseWorkspace, workspaceStarted;
    const sessionEntered = new Promise(resolve => { sessionStarted = resolve; });
    const workspaceEntered = new Promise(resolve => { workspaceStarted = resolve; });
    const workspaceReady = new Promise(resolve => { releaseWorkspace = resolve; });
    client.auth.getSession = () => {
        sessionStarted();
        return new Promise(resolve => { releaseSession = resolve; });
    };
    const originalFetch = state.supabaseFetch;
    state.supabaseFetch = async (...args) => {
        if (args[0] === 'rpc/get_my_access_context') {
            workspaceStarted();
            await workspaceReady;
        }
        return originalFetch(...args);
    };
    const initialization = state.init();
    await sessionEntered;
    assert.equal(state.authBootstrapping, true);
    assert.equal(state.session, null);
    releaseSession({ data: { session } });
    await workspaceEntered;
    assert.equal(state.authBootstrapping, true);
    assert.equal(state.session.user.id, USER);
    assert.equal(state.user, null);
    releaseWorkspace();
    await initialization;
    assert.equal(state.authBootstrapping, false);
    assert.equal(state.user.workspace_id, STAFF_WORKSPACE);
});

test('sem sessão ou com falha de leitura, a verificação libera o login', async () => {
    for (const fail of [false, true]) {
        const { state, client } = runtime();
        client.auth.getSession = async () => {
            if (fail) throw new Error('Session unavailable');
            return { data: { session: null } };
        };
        await state.init();
        assert.equal(state.authBootstrapping, false);
        assert.equal(state.session, null);
        assert.equal(state.initInFlight, false);
        assert.equal(Boolean(state.authError), fail);
    }
});

test('configuração inválida libera o carregamento e apresenta erro em vez de travar', async () => {
    const { state, context } = runtime();
    vm.runInContext('supabaseClient = null', context);
    await state.init();
    assert.equal(state.authBootstrapping, false);
    assert.equal(state.initInFlight, false);
    assert.match(state.error, /Erro de Configuração/);
});

test('init de dono de A e técnico de B carrega somente o contexto escolhido, sem herdar admin', async () => {
    const { state, storage, events, requests } = runtime();
    await state.init();
    assert.equal(state.user.workspace_id, STAFF_WORKSPACE);
    assert.equal(state.user.id, EMPLOYEE);
    assert.equal(state.user.auth_user_id, USER);
    assert.equal(state.hasRole('admin'), false);
    assert.equal(state.hasRole('tecnico'), true);
    assert.equal(state.adminDashboardFilters.technician, EMPLOYEE);
    assert.equal(state.view, 'tech_orders');
    assert.equal(state.bootstrapDone, true);
    assert.ok(events.includes('tickets:tech_orders'));
    assert.equal(storage.has('techassist_employee'), false);
    assert.equal(requests.find(item => item.endpoint === 'rpc/get_my_access_context').payload.p_workspace_id, STAFF_WORKSPACE);
    assert.ok(state.trackerConfig.colors.background);
});

test('init de tester preserva o fluxo de teste e não carrega dashboard administrativo', async () => {
    const { state, events } = runtime(['tester']);
    await state.init();
    assert.equal(state.view, 'tester_bench');
    assert.equal(state.hasRole('admin'), false);
    assert.ok(events.includes('tickets:tester_bench'));
    assert.equal(state.bootstrapDone, true);
});

test('revogação local fecha OS/modais e pede nova entrada em B, mantendo vínculo de proprietário A', async () => {
    const { state, events } = runtime();
    await state.init();
    state.employeeSessionLastValidatedAt = 0;
    state.selectedTicket = { id: 'ticket-b' };
    state.modals.viewTicket = true;
    state.supabaseFetch = async endpoint => {
        if (endpoint === 'rpc/get_my_access_context') throw Object.assign(new Error('Reautenticacao necessaria'), { status: 400 });
        if (endpoint === 'rpc/list_my_pending_invitations') return [];
        if (endpoint === 'rpc/list_my_workspaces') return [
            { workspace_id: OWNER_WORKSPACE, member_kind: 'owner', roles: ['admin'] },
            { workspace_id: STAFF_WORKSPACE, member_kind: 'employee', roles: ['tecnico'], requires_reauthentication: true }
        ];
        throw new Error('Unexpected request');
    };
    assert.equal(await state.revalidateEmployeeSession(), false);
    assert.equal(state.user, null);
    assert.equal(state.selectedTicket, null);
    assert.equal(state.modals.viewTicket, false);
    assert.equal(state.view, 'access_hub');
    assert.equal(state.reauthWorkspaceId, STAFF_WORKSPACE);
    assert.ok(state.workspaces.some(item => item.workspace_id === OWNER_WORKSPACE));
    assert.ok(events.includes('channels_removed'));
    assert.ok(events.includes('previews_cleared'));
});
