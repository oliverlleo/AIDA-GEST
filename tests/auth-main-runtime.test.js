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
        ['sb-example-auth-token', 'opaque-session-not-read-by-presentation'],
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
    const firstpaintAttributes = new Map();
    const sandbox = {
        console: { log() {}, warn() {}, error() {} }, Date, URL, TextEncoder,
        SUPABASE_CONFIG: { URL: 'https://example.supabase.co', KEY: 'publishable-key' },
        supabase: { createClient: (_url, _key, options) => { assert.equal(options.auth.flowType, 'pkce'); assert.equal(options.auth.storageKey, 'sb-example-auth-token'); return client; } },
        document: { visibilityState: 'visible', addEventListener() {}, querySelector: () => ({}), documentElement: {
            setAttribute: (key, value) => firstpaintAttributes.set(key, value),
            removeAttribute: key => firstpaintAttributes.delete(key)
        } },
        location: { href: 'https://oliverlleo.github.io/AIDA-GEST/app.html', reload: () => events.push('reload'), replace: () => events.push('replace') },
        history: { replaceState() {} }, addEventListener() {},
        localStorage: { get length() { return storage.size; }, key: index => [...storage.keys()][index], getItem: key => storage.get(key) || null, setItem: (key, value) => storage.set(key, value), removeItem: key => storage.delete(key) },
        sessionStorage: { getItem: () => null, setItem() {}, removeItem() {} },
        setInterval: () => 1, clearTimeout() {}, setTimeout: callback => { timeouts.push(callback); return timeouts.length; },
        AIDAStorageService: { clearLocalPhotoPreviews: () => events.push('previews_cleared') }
    };
    sandbox.window = sandbox;
    const context = vm.createContext(sandbox);
    for (const file of ['js/auth-firstpaint.js', 'js/modules/feature-config.js', 'js/modules/config-helpers.js', 'js/modules/ticket-context.js', 'js/modules/customer-service.js', 'js/modules/inventory-catalog-service.js', 'js/modules/auth-session-service.js', 'js/main.js']) {
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
    return { state, context, storage, events, requests, session, client, firstpaintAttributes, listener: () => listener, timeouts };
}

test('bootstrap permanece ativo durante a restauração da sessão e da empresa', async () => {
    const { state, client, session, firstpaintAttributes } = runtime();
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
    assert.equal(firstpaintAttributes.has('data-auth-pending'), true);
    releaseSession({ data: { session } });
    await workspaceEntered;
    assert.equal(state.authBootstrapping, true);
    assert.equal(state.session.user.id, USER);
    assert.equal(state.user, null);
    assert.equal(firstpaintAttributes.has('data-auth-pending'), true);
    releaseWorkspace();
    await initialization;
    assert.equal(state.authBootstrapping, false);
    assert.equal(state.user.workspace_id, STAFF_WORKSPACE);
    assert.equal(firstpaintAttributes.has('data-auth-pending'), false);
});

test('agenda consulta somente settings da empresa e preserva defaults sem linha ou com settings parciais', async () => {
    const { state } = runtime(['admin']);
    state.user = { workspace_id: STAFF_WORKSPACE };
    state.scheduleManagement.techConfig.technician_id = EMPLOYEE;
    const workDays = JSON.stringify(state.scheduleManagement.techConfig.workDays);
    const requests = [];
    state.supabaseFetch = async (endpoint) => { requests.push(endpoint); return []; };
    await state.loadTechConfig();
    assert.equal(JSON.stringify(state.scheduleManagement.techConfig.workDays), workDays);
    assert.equal(state.scheduleManagement.techConfig.technician_id, EMPLOYEE);
    assert.equal(state.loading, false);
    assert.equal(requests[0], `technician_schedule_settings?select=settings&workspace_id=eq.${STAFF_WORKSPACE}&technician_id=eq.${EMPLOYEE}&limit=1`);
    state.supabaseFetch = async () => [{ settings: { slotDuration: 45, hasBreak: false } }];
    await state.loadTechConfig();
    assert.equal(state.scheduleManagement.techConfig.slotDuration, 45);
    assert.equal(state.scheduleManagement.techConfig.hasBreak, false);
    assert.equal(JSON.stringify(state.scheduleManagement.techConfig.workDays), workDays);
});

test('agenda salva por REST com conflito tecnico e nao espera linha no upsert', async () => {
    const { state } = runtime(['admin']);
    state.user = { workspace_id: STAFF_WORKSPACE };
    state.scheduleManagement.techConfig.technician_id = EMPLOYEE;
    state.modals.techScheduleSettings = true;
    let request;
    state.supabaseFetch = async (endpoint, method, body, options) => { request = { endpoint, method, body, options }; return null; };
    await state.saveTechConfig();
    assert.equal(request.endpoint, 'technician_schedule_settings?on_conflict=technician_id');
    assert.equal(request.method, 'POST');
    assert.equal(request.body.technician_id, EMPLOYEE);
    assert.equal(request.body.workspace_id, STAFF_WORKSPACE);
    assert.equal(request.body.settings.slotDuration, state.scheduleManagement.techConfig.slotDuration);
    assert.equal(request.options.upsert, true);
    assert.equal(request.options.returnRepresentation, false);
    assert.equal(state.modals.techScheduleSettings, false);
    assert.equal(state.loading, false);
});

test('sem sessão ou com falha de leitura, a verificação libera o login', async () => {
    for (const fail of [false, true]) {
        const { state, client, firstpaintAttributes } = runtime();
        client.auth.getSession = async () => {
            if (fail) throw new Error('Session unavailable');
            return { data: { session: null } };
        };
        await state.init();
        assert.equal(state.authBootstrapping, false);
        assert.equal(state.session, null);
        assert.equal(state.initInFlight, false);
        assert.equal(Boolean(state.authError), fail);
        assert.equal(firstpaintAttributes.has('data-auth-pending'), false);
    }
});

test('configuração inválida libera o carregamento e apresenta erro em vez de travar', async () => {
    const { state, context, firstpaintAttributes } = runtime();
    vm.runInContext('supabaseClient = null', context);
    await state.init();
    assert.equal(state.authBootstrapping, false);
    assert.equal(state.initInFlight, false);
    assert.match(state.error, /Erro de Configuração/);
    assert.equal(firstpaintAttributes.has('data-auth-pending'), false);
});

test('armazenamento bloqueado não trava a restauração nem mantém o login oculto', async () => {
    const { state, client, context, firstpaintAttributes } = runtime();
    const denyStorage = () => { throw new Error('SecurityError'); };
    context.sessionStorage = { getItem: denyStorage, setItem: denyStorage, removeItem: denyStorage };
    context.localStorage = { get length() { return denyStorage(); }, key: denyStorage, getItem: denyStorage, setItem: denyStorage, removeItem: denyStorage };
    client.auth.getSession = async () => ({ data: { session: null } });
    await state.init();
    assert.equal(state.authBootstrapping, false);
    assert.equal(state.initInFlight, false);
    assert.equal(state.session, null);
    assert.equal(firstpaintAttributes.has('data-auth-pending'), false);
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

test('limite no lote de fotos interrompe os próximos envios e conserva as fotos já anexadas', async () => {
    for (const target of ['new', 'existing']) {
        const { state, context } = runtime();
        const notices = [], calls = [];
        const photos = ['previous-photo'];
        state.ticketForm = { id: 'draft-ticket', photos, client_name: 'Cliente do cadastro' };
        state.selectedTicket = { id: 'saved-ticket', photos_urls: photos, client_name: 'Cliente salvo' };
        state.modals.viewTicket = target === 'existing';
        context.AIDATicketContext.setModalContext('saved-ticket', 'viewTicket');
        state.notify = (message, type) => notices.push({ message, type });
        context.AIDAStorageService.uploadTicketPhoto = async (file, ticketId) => {
            calls.push({ name: file.name, ticketId });
            if (file.name === 'limited') throw Object.assign(new Error('Aguarde 25 segundos e tente novamente.'), { status: 429 });
            return file.name;
        };
        const event = { target: { value: 'selected-files', files: [{ name: 'added-photo' }, { name: 'limited' }, { name: 'must-not-upload' }] } };
        await state.handlePhotoUpload(event, target);
        assert.deepEqual(calls.map(call => call.name), ['added-photo', 'limited']);
        assert.ok(calls.every(call => call.ticketId === (target === 'new' ? 'draft-ticket' : 'saved-ticket')));
        assert.deepEqual(photos, ['previous-photo', 'added-photo']);
        assert.equal(notices.length, 1);
        assert.match(notices[0].message, /Aguarde 25 segundos/);
        assert.equal(notices[0].type, 'error');
        assert.equal(event.target.value, '');
        assert.equal(state.ticketForm.client_name, 'Cliente do cadastro');
        assert.equal(state.selectedTicket.client_name, 'Cliente salvo');
        assert.equal(state.loading, false);
    }
});


test('rate limit na revalidação mantém vínculo, OS e rascunho', async () => {
    const { state, events } = runtime();
    await state.init();
    state.selectedTicket = { id: 'os-draft', revision: 3, tech_notes: 'rascunho' };
    state.modals.viewTicket = true;
    state.employeeSessionLastValidatedAt = 0;
    state.supabaseFetch = async () => { throw Object.assign(new Error('Aguarde'), { status: 429, retryAfter: 20 }); };
    assert.equal(await state.revalidateEmployeeSession(), true);
    assert.equal(state.user.workspace_id, STAFF_WORKSPACE);
    assert.equal(state.selectedTicket.tech_notes, 'rascunho');
    assert.equal(state.modals.viewTicket, true);
    assert.equal(events.includes('channels_removed'), false);
    await assert.rejects(state.revalidateEmployeeSession(true), error => error.status === 429);
    assert.equal(state.user.workspace_id, STAFF_WORKSPACE);
});

test('resposta de fila e contagens antigas não sobrescreve filtros novos', async () => {
    const { state } = runtime(['admin']);
    state.user = { workspace_id: STAFF_WORKSPACE };
    const pending = [];
    state.notify = () => {};
    state.supabaseFetch = async () => new Promise(resolve => pending.push(resolve));
    const queue = state.fetchHomeOperationalQueue();
    state.homeOperationalFilters.search = 'novo filtro';
    pending.splice(0).forEach(resolve => resolve({ counts: { all: 999 }, queues: {} }));
    await queue;
    assert.notEqual(state.homeOperationalCounts.all, 999);
    const counts = state.fetchKanbanOperationalCounts();
    state.kanbanOperationalFilters.status = 'Aprovacao';
    pending.splice(0).forEach(resolve => resolve({ counts: { all: 999 } }));
    await counts;
    assert.notEqual(state.kanbanOperationalCounts.all, 999);
});


test('fila em segundo plano propaga 429 para o backoff sem expulsar usuário', async () => {
    const { state } = runtime(['admin']);
    state.user = { workspace_id: STAFF_WORKSPACE };
    state.supabaseFetch = async () => { throw Object.assign(new Error('limited'), { status: 429, retryAfter: 30 }); };
    await assert.rejects(state.fetchHomeOperationalQueue({ background: true }), error => error.status === 429);
    assert.equal(state.user.workspace_id, STAFF_WORKSPACE);
    assert.equal(state.homeOperationalLoading, false);
});

test('conflito mantém formulário de análise aberto e sucesso o fecha', async () => {
    const { state } = runtime(['tecnico']);
    state.resolveTicket = () => ({ id: 'os-analysis', status: 'Analise Tecnica' });
    state.isInventoryEnabled = () => false;
    state.isPartsControlEnabled = () => false;
    state.modals.finishAnalysis = true;
    state.finishAnalysis = async () => false;
    await state.confirmFinishAnalysisKanban();
    assert.equal(state.modals.finishAnalysis, true);
    state.finishAnalysis = async () => true;
    await state.confirmFinishAnalysisKanban();
    assert.equal(state.modals.finishAnalysis, false);
});

test('agenda obtém revisão ausente na abertura e congela o snapshot do formulário', async () => {
    const { state } = runtime(['admin']);
    state.user = { workspace_id: STAFF_WORKSPACE };
    const appointment = { id: 'appointment-a', ticket_id: 'os-a', type: 'analysis' };
    const calls = [];
    state.supabaseFetch = async endpoint => { calls.push(endpoint); return [{ ...appointment, revision: 7 }]; };
    await state.openAppointmentActionMenu(appointment, '2026-10-16', { start_time: '2026-10-16T08:00:00', end_time: '2026-10-16T09:00:00' });
    assert.equal(calls.length, 1);
    assert.match(calls[0], /^ticket_appointments\?select=\*/);
    assert.equal(state.scheduleManagement.editingAppointment.original.revision, 7);
    appointment.revision = 99;
    assert.equal(state.scheduleManagement.editingAppointment.original.revision, 7);
    assert.equal(state.modals.rescheduleAppointment, true);
});

test('recebimento guarda revisão da compra na abertura e preserva formulário no conflito', async () => {
    const { state, context } = runtime(['admin']);
    state.notify = () => {};
    let savedArguments;
    context.AIDAInventoryManagementService = {
        loadPurchase: async () => ({ purchase: { revision: 9 }, items: [] }),
        receivePurchase: async (...args) => { savedArguments = args; throw Object.assign(new Error('conflito'), { status: 409 }); }
    };
    await state.openInventoryReceipt({ id: 'purchase-a', supplier_name: 'Fornecedor teste' });
    assert.equal(state.inventory.receiptVersion, 9);
    await state.submitInventoryReceipt();
    assert.equal(savedArguments[4], 9);
    assert.equal(state.modals.inventoryReceipt, true);
});


function loadSyncForCommands(context) {
    vm.runInContext(fs.readFileSync(path.join(root, 'js/modules/workspace-sync-service.js'), 'utf8'), context);
}

test('agendamento continua aprovação com revisão do próprio recibo e preserva laudo digitado', async () => {
    const { state, context } = runtime(['admin']);
    loadSyncForCommands(context);
    state.user = { workspace_id: STAFF_WORKSPACE };
    state.selectedTicket = { id: 'os-command', revision: 4, tech_notes: 'base', status: 'Aprovacao' };
    context.AIDAWorkspaceSyncService.captureTicket(state, state.selectedTicket);
    state.selectedTicket.tech_notes = 'rascunho técnico';
    state.schedulePanelTicket = JSON.parse(JSON.stringify(state.selectedTicket));
    state.schedulePanelTechnicianId = EMPLOYEE;
    state.schedulePanelMode = 'repair';
    state.schedulePanelAfterSave = 'approveRepair';
    state.schedulePanelOpen = true;
    state.fetchTicketAppointments = async () => {};
    state.notify = () => {};
    let continued = 0, capturedOptions;
    context.AIDATicketActions = { completeBudgetApproval: async (ticket, deps) => {
        continued++;
        assert.equal(ticket.revision, 6);
        assert.equal(deps.resolveTicket('os-command').revision, 6);
        assert.equal(state.selectedTicket.tech_notes, 'rascunho técnico');
        return true;
    } };
    state.supabaseFetch = async (endpoint, method, payload, options) => {
        capturedOptions = options;
        assert.equal(endpoint, 'rpc/create_ticket_appointment');
        state.tickets = [{ id: 'os-command', revision: 99 }];
        return { ticket_id: 'os-command', ticket_revision: 6, ticket_updates: { repair_scheduled: true, repair_scheduled_at: 'confirmed', technician_id: EMPLOYEE } };
    };
    await state.selectScheduleSlot('2026-10-16', { start: '08:00', end: '09:00' });
    assert.equal(capturedOptions.ticketVersion.revision, 4);
    assert.equal(continued, 1);
    assert.equal(state.selectedTicket.revision, 6);
    assert.equal(state.ticketModalSnapshot.revision, 6);
    assert.equal(state.schedulePanelOpen, false);
});

test('solicitação de peças usa snapshot original e continua análise com recibo confirmado', async () => {
    const { state, context } = runtime(['admin']);
    loadSyncForCommands(context);
    state.user = { workspace_id: STAFF_WORKSPACE };
    state.selectedTicket = { id: 'os-command', revision: 4, tech_notes: 'base', parts_needed: null };
    context.AIDAWorkspaceSyncService.captureTicket(state, state.selectedTicket);
    state.selectedTicket.tech_notes = 'laudo ainda digitado';
    state.inventory.partRequest = { ticketId: 'os-command', ticketSnapshot: JSON.parse(JSON.stringify(state.selectedTicket)), stage: 'analysis', allocateNow: false, afterSubmit: 'finishAnalysis', items: [{ item_id: 'item-a', name: 'Tela', quantity: 1 }] };
    state.modals.inventoryPartRequest = true;
    state.notify = () => {};
    let continued = 0, originalRevision;
    vm.runInContext(fs.readFileSync(path.join(root, 'js/modules/inventory-actions.js'), 'utf8'), context);
    state.supabaseFetch = async (endpoint, method, payload, options) => {
        assert.equal(endpoint, 'rpc/request_ticket_inventory_parts');
        originalRevision = options.ticketVersion.revision;
        state.tickets = [{ id: 'os-command', revision: 99 }];
        return { ticket_id: 'os-command', ticket_revision: 6, ticket_updates: { parts_needed: '1 x Tela', parts_status: 'Pendente' } };
    };
    context.AIDATicketActions = { finishAnalysis: async (ticket, deps) => {
        continued++;
        assert.equal(ticket.revision, 6);
        assert.equal(deps.resolveTicket('os-command').revision, 6);
        assert.equal(state.selectedTicket.tech_notes, 'laudo ainda digitado');
        return true;
    } };
    await state.submitInventoryPartRequest();
    assert.equal(originalRevision, 4);
    assert.equal(continued, 1);
    assert.equal(state.selectedTicket.revision, 6);
    assert.equal(state.ticketModalSnapshot.revision, 6);
    assert.equal(state.modals.inventoryPartRequest, false);
});

test('conflito antes de registrar peças não executa continuação nem apaga formulário', async () => {
    const { state, context } = runtime(['admin']);
    loadSyncForCommands(context);
    state.selectedTicket = { id: 'os-command', revision: 4, tech_notes: 'rascunho' };
    state.inventory.partRequest = { ticketId: 'os-command', ticketSnapshot: { ...state.selectedTicket }, afterSubmit: 'finishAnalysis', items: [] };
    state.modals.inventoryPartRequest = true; state.notify = () => {};
    let continued = 0;
    context.AIDAInventoryActions = { requestTicketParts: async () => { throw Object.assign(new Error('conflito'), { status: 409 }); } };
    context.AIDATicketActions = { finishAnalysis: async () => { continued++; } };
    await state.submitInventoryPartRequest();
    assert.equal(continued, 0);
    assert.equal(state.modals.inventoryPartRequest, true);
    assert.equal(state.selectedTicket.tech_notes, 'rascunho');
    assert.equal(state.selectedTicket.revision, 4);
});

test('fechar a OS permite usar a revisão atual do card sem reaproveitar modal antigo', () => {
    const { state } = runtime(['admin']);
    state.selectedTicket = { id: 'os-command', revision: 4 };
    const card = { id: 'os-command', revision: 8 };
    state.tickets = [card];
    state.modals.viewTicket = false;
    assert.equal(state.resolveTicket('os-command'), card);
    state.modals.outcome = true;
    assert.equal(state.resolveTicket('os-command'), state.selectedTicket);
});
