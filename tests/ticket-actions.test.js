const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

global.window = global;
require('../js/modules/warranty-service.js');
require('../js/modules/ticket-actions.js');
require('../js/modules/workflow-rules.js');
require('../js/modules/workspace-sync-service.js');

test('conflito na mudança de fase não inicia nem encerra o agendamento', async () => {
    const ticket = { id: 'ticket-conflict', revision: 4, tech_notes: 'rascunho' };
    for (const action of ['startAnalysis', 'finishAnalysis']) {
        let rpcCalls = 0;
        const result = await global.AIDATicketActions[action](ticket, {
            resolveTicket: () => ticket,
            state: { selectedTicket: ticket, analysisForm: {} },
            isPartsControlEnabled: () => false,
            getLogContext: () => ({ device: 'Aparelho', client: 'Cliente' }),
            updateStatus: async () => false,
            supabaseFetch: async () => { rpcCalls++; }
        });
        assert.equal(result, false);
        assert.equal(rpcCalls, 0);
        assert.equal(ticket.tech_notes, 'rascunho');
    }
});

test('conflito nos testes finais mantém formulário aberto e não anuncia sucesso ou agenda reparo', async () => {
    const ticket = { id: 'test-conflict', status: 'Teste Final', revision: 2 };
    for (const success of [true, false]) {
        const events = [];
        const result = await global.AIDATicketActions.concludeTest(success, {
            resolveTicket: () => ticket,
            state: { user: { name: 'Tester' }, selectedTicket: ticket,
                testFailureData: { reason: 'Defeito', newDeadline: '2026-10-20T12:00', newPriority: 'Alta' },
                openSchedulePanel: () => events.push('schedule') },
            getLogContext: () => ({ device: 'Aparelho', client: 'Cliente' }),
            toUTC: value => value, closeModal: () => events.push('closed'), notify: () => events.push('success'),
            isAppointmentTypeEnabled: () => true, updateStatus: async () => false
        });
        assert.equal(result, false);
        assert.deepEqual(events, []);
    }
});

test('compra conserva o snapshot do início do formulário mesmo depois da lista sincronizar', async () => {
    const original = { id: 'purchase-os', revision: 4, supplier_purchases: [], parts_needed: 'Tela' };
    const fresh = { ...original, revision: 5, parts_needed: 'Bateria' };
    let sent;
    await global.AIDATicketActions.submitPurchase({
        state: { tickets: [fresh], purchaseFlow: { ticketId: original.id, ticketSnapshot: original, supplierName: 'Fornecedor', items: [{ name: 'Tela', quantity: 1 }] } },
        isModuleEnabled: () => false, getLogContext: () => ({ device: 'Aparelho', client: 'Cliente' }),
        mutateTicket: async ticket => { sent = ticket; return false; }, closeModal: () => { throw new Error('must stay open'); }
    });
    assert.equal(sent.revision, 4);
    assert.equal(sent.parts_needed, 'Tela');
});

test('aprovação com estoque agenda usando a versão confirmada pelo próprio comando', async () => {
    const ticket = { id: 'inventory-approval', revision: 4, status: 'Aprovacao', parts_needed: 'Tela' };
    let sentVersion, scheduledRevision;
    const state = { selectedTicket: null, openSchedulePanel: (_mode, _tech, snapshot) => { scheduledRevision = snapshot.revision; } };
    const result = await global.AIDATicketActions.approveRepair(ticket, {
        state, resolveTicket: () => ticket, isInventoryEnabled: () => true, setLoading() {},
        supabaseFetch: async (_endpoint, _method, _body, options) => {
            sentVersion = options.ticketVersion;
            return { route: 'schedule_repair', ticket_id: ticket.id, ticket_revision: 6,
                ticket_updates: { parts_needed: 'Tela', parts_status: 'Reservado', budget_status: 'Aprovado' } };
        },
        applyCommandReceipt: (target, receipt) => global.AIDAWorkspaceSyncService.applyCommandReceipt(state, target, receipt),
        fetchTickets: async () => {}, fetchGlobalLogs: async () => {}, notify() {}
    });
    assert.equal(result, true);
    assert.deepEqual(sentVersion, { id: ticket.id, revision: 4 });
    assert.equal(scheduledRevision, 6);
    assert.equal(ticket.parts_status, 'Reservado');
});

test('tester salva somente checklist final e nega fase ou OS selecionada incorreta', async () => {
    const ticket = { id: 'test-os', status: 'Teste Final' };
    const selected = { ...ticket, checklist_final_data: [{ item: 'Tela', ok: true }], tech_notes: 'Tentativa indevida', parts_needed: 'Tentativa indevida', photos_urls: ['arquivo-indevido'], checklist_data: [{ item: 'Entrada', ok: false }] };
    let mutation, calls = 0;
    const hasRole = role => role === 'tester';
    const deps = {
        resolveTicket: () => ticket,
        state: { hasRole, selectedTicket: selected },
        notify() {},
        mutateTicket: async (_ticket, _action, updates) => { calls++; mutation = updates; return true; }
    };
    assert.equal(global.AIDAWorkflowRules.canExecuteAction(ticket, 'saveTicketChanges', hasRole, {}), false);
    assert.equal(global.AIDAWorkflowRules.canExecuteAction(ticket, 'saveTicketChanges', hasRole, { test_flow: 'tester' }), true);
    await global.AIDATicketActions.saveTicketChanges(deps);
    assert.deepEqual(mutation, { checklist_final_data: selected.checklist_final_data });
    assert.equal(calls, 1);
    selected.id = 'different-os';
    assert.equal(await global.AIDATicketActions.saveTicketChanges(deps), false);
    assert.equal(calls, 1);
    selected.id = ticket.id;
    ticket.status = 'Retirada Cliente';
    assert.equal(global.AIDAWorkflowRules.canExecuteAction(ticket, 'saveTicketChanges', hasRole, {}), false);
    assert.equal(await global.AIDATicketActions.saveTicketChanges(deps), false);
    assert.equal(calls, 1);
});

test('conclusao do tester persiste checklist selecionado no sucesso e na falha', async () => {
    for (const success of [true, false]) {
        const ticket = { id: 'test-os', status: 'Teste Final', checklist_final_data: [{ item: 'Tela', ok: false }] };
        const selected = { ...ticket, checklist_final_data: [{ item: 'Tela', ok: true }], tech_notes: 'Nao copiar' };
        let mutation;
        await global.AIDATicketActions.concludeTest(success, {
            resolveTicket: () => ticket,
            state: { user: { name: 'Tester' }, selectedTicket: selected, testFailureData: { reason: 'Falha no teste', newDeadline: '2026-10-16T12:00', newPriority: 'Alta' } },
            getLogContext: () => ({ client: 'Cliente', device: 'Aparelho' }),
            closeModal() {}, notify() {}, toUTC: value => value,
            isAppointmentTypeEnabled: () => false,
            updateStatus: async (_ticket, status, updates) => { mutation = { status, updates }; }
        });
        assert.equal(mutation.status, success ? 'Retirada Cliente' : 'Andamento Reparo');
        assert.deepEqual(mutation.updates.checklist_final_data, selected.checklist_final_data);
        assert.equal(mutation.updates.tech_notes, undefined);
        if (success) assert.deepEqual(Object.keys(mutation.updates), ['checklist_final_data']);
    }
});

test('tecnico com papel tester adicional preserva os cinco campos operacionais', async () => {
    const ticket = { id: 'technical-os', technician_id: 'current-technician', status: 'Andamento Reparo' };
    const selected = { ...ticket, tech_notes: 'Diagnostico', parts_needed: 'Tela', checklist_data: [], checklist_final_data: [{ item: 'Tela', ok: true }], photos_urls: ['foto'], budget_value: 999, deleted_at: 'nao copiar' };
    let updates;
    await global.AIDATicketActions.saveTicketChanges({
        resolveTicket: () => ticket,
        state: { user: { id: 'current-technician' }, hasRole: role => ['tecnico', 'tester'].includes(role), selectedTicket: selected },
        notify() {},
        mutateTicket: async (_ticket, _action, payload) => { updates = payload; return true; }
    });
    assert.deepEqual(updates, {
        tech_notes: selected.tech_notes, parts_needed: selected.parts_needed,
        checklist_data: selected.checklist_data, checklist_final_data: selected.checklist_final_data,
        photos_urls: selected.photos_urls
    });
});

function makeTicket(overrides = {}) {
    return {
        id: 'ticket-id',
        technician_id: 'technician-id',
        client_name: 'Cliente',
        contact_info: '(11) 99999-9999',
        device_model: 'Aparelho',
        parts_needed: null,
        repair_scheduled: false,
        repair_scheduled_at: null,
        ...overrides
    };
}

test('tecnico que testa OS de outro responsavel salva somente checklist final', async () => {
    const ticket = { id: 'other-final', technician_id: 'other-technician', status: 'Teste Final' };
    const selected = { ...ticket, tech_notes: 'Não enviar', photos_urls: ['não enviar'], checklist_final_data: [{ item: 'Tela', ok: true }] };
    let updates;
    await global.AIDATicketActions.saveTicketChanges({
        resolveTicket: () => ticket,
        state: { user: { id: 'current-technician' }, hasRole: role => ['tecnico', 'tester'].includes(role), selectedTicket: selected },
        notify() {}, mutateTicket: async (_ticket, _action, payload) => { updates = payload; return true; }
    });
    assert.deepEqual(updates, { checklist_final_data: selected.checklist_final_data });
});

test('tecnico nao abre OS com aprovacao comercial antecipada', async () => {
    let notice;
    await global.AIDATicketActions.createTicket({
        state: { ticketForm: { budget_approved: true }, hasRole: role => role === 'tecnico' },
        notify: message => { notice = message; }
    });
    assert.match(notice, /administrador ou atendente/);
});

function makeApprovalDeps(ticket, overrides = {}) {
    return {
        resolveTicket: () => ticket,
        isPartsControlEnabled: () => false,
        isAppointmentTypeEnabled: () => true,
        getLogContext: () => ({ client: 'Cliente', device: 'Aparelho' }),
        updateStatus: async () => true,
        state: { openSchedulePanel: () => {} },
        ...overrides
    };
}

test('aprovar sem pecas exige agendamento antes de avancar para reparo', async () => {
    const ticket = makeTicket();
    let scheduleArgs;
    let updateCalls = 0;

    const result = await global.AIDATicketActions.approveRepair(ticket, makeApprovalDeps(ticket, {
        updateStatus: async () => {
            updateCalls += 1;
            return true;
        },
        state: {
            openSchedulePanel: (...args) => {
                scheduleArgs = args;
            }
        }
    }));

    assert.equal(result, false);
    assert.equal(updateCalls, 0);
    assert.deepEqual(scheduleArgs, ['repair', 'technician-id', ticket, 'approveRepair']);
});

test('aprovar com reparo ja agendado avanca diretamente para reparo', async () => {
    const ticket = makeTicket({ repair_scheduled_at: '2026-07-24T13:00:00Z' });
    let updateArgs;

    const result = await global.AIDATicketActions.approveRepair(ticket, makeApprovalDeps(ticket, {
        updateStatus: async (...args) => {
            updateArgs = args;
            return true;
        }
    }));

    assert.equal(result, true);
    assert.equal(updateArgs[1], 'Andamento Reparo');
    assert.deepEqual(updateArgs[2], { budget_status: 'Aprovado' });
});

test('aprovar com agendamento desativado avanca diretamente para reparo', async () => {
    const ticket = makeTicket();
    let nextStatus;

    await global.AIDATicketActions.approveRepair(ticket, makeApprovalDeps(ticket, {
        isAppointmentTypeEnabled: () => false,
        updateStatus: async (_ticket, status) => {
            nextStatus = status;
            return true;
        }
    }));

    assert.equal(nextStatus, 'Andamento Reparo');
});

test('aprovar com compra de pecas envia para compra sem abrir agenda', async () => {
    const ticket = makeTicket({ parts_needed: 'Tela' });
    let nextStatus;
    let scheduleOpened = false;

    await global.AIDATicketActions.approveRepair(ticket, makeApprovalDeps(ticket, {
        isPartsControlEnabled: () => true,
        updateStatus: async (_ticket, status) => {
            nextStatus = status;
            return true;
        },
        state: { openSchedulePanel: () => { scheduleOpened = true; } }
    }));

    assert.equal(nextStatus, 'Compra Peca');
    assert.equal(scheduleOpened, false);
});

test('garantia nao coberta abre uma nova OS sem mover o retorno para reparo', async () => {
    const ticket = makeTicket({
        warranty_claim: true,
        warranty_status: 'not_covered'
    });
    let openedTicket;
    let updateCalls = 0;

    const result = await global.AIDATicketActions.approveRepair(ticket, makeApprovalDeps(ticket, {
        openPaidServiceFromWarranty: value => { openedTicket = value; },
        updateStatus: async () => {
            updateCalls += 1;
            return true;
        }
    }));

    assert.equal(result, false);
    assert.equal(openedTicket, ticket);
    assert.equal(updateCalls, 0);
});

test('decisao da garantia e salva pelo RPC e encerra o agendamento da analise', async () => {
    const ticket = makeTicket({
        warranty_claim: true,
        warranty_status: 'pending',
        status: 'Analise Tecnica'
    });
    const calls = [];
    const state = {
        analysisForm: {
            needsParts: false,
            partsList: '',
            warrantyCovered: 'yes',
            warrantyDiagnosis: 'Falha confirmada no componente substituido.',
            warrantyCause: 'Defeito recorrente da peca.',
            warrantyEvidence: 'O defeito esta diretamente ligado ao reparo original.'
        },
        selectedTicket: { ...ticket, tech_notes: 'Teste tecnico realizado.' },
        modals: { finishAnalysis: true }
    };

    const result = await global.AIDATicketActions.finishWarrantyAnalysis(ticket, {
        resolveTicket: () => ticket,
        state,
        isPartsControlEnabled: () => true,
        setLoading: value => calls.push({ path: 'loading', value }),
        supabaseFetch: async (path, _method, payload) => {
            calls.push({ path, payload });
            return path === 'rpc/complete_warranty_analysis'
                ? { ...ticket, warranty_status: 'covered', status: 'Andamento Reparo' }
                : null;
        },
        getLogContext: () => ({ client: 'Cliente', device: 'Aparelho' }),
        logTicketAction: async (...args) => { calls.push({ path: 'log', args }); },
        notify: (...args) => { calls.push({ path: 'notify', args }); },
        fetchTickets: async () => { calls.push({ path: 'fetchTickets' }); },
        fetchGlobalLogs: async () => { calls.push({ path: 'fetchGlobalLogs' }); }
    });

    assert.equal(result, true);
    assert.equal(state.modals.finishAnalysis, false);
    assert.equal(state.selectedTicket.warranty_status, 'covered');
    assert.equal(
        calls.find(call => call.path === 'rpc/complete_warranty_analysis').payload.p_covered,
        true
    );
    assert.deepEqual(
        calls.find(call => call.path === 'rpc/complete_ticket_appointment').payload,
        { p_ticket_id: ticket.id, p_type: 'analysis' }
    );
});

function makeBudgetDeps(ticket, overrides = {}) {
    return {
        resolveTicket: () => ticket,
        isWhatsAppDisabled: () => false,
        getLogContext: () => ({ client: 'Cliente', device: 'Aparelho' }),
        mutateTicket: async () => true,
        isModuleEnabled: () => false,
        getTrackingLink: () => null,
        notify: () => {},
        ...overrides
    };
}

test('orcamento sem telefone continua sendo enviado sem abrir WhatsApp', async () => {
    const ticket = makeTicket({ contact_info: null });
    let mutateCalls = 0;
    let notice;
    let openCalls = 0;
    const originalOpen = global.open;
    global.open = () => { openCalls += 1; };

    try {
        await global.AIDATicketActions.sendBudget(ticket, makeBudgetDeps(ticket, {
            mutateTicket: async () => {
                mutateCalls += 1;
                return true;
            },
            notify: (message, type) => { notice = { message, type }; }
        }));

        assert.equal(mutateCalls, 1);
        assert.equal(openCalls, 0);
        assert.equal(notice.type, undefined);
        assert.match(notice.message, /marcado como Enviado/);
        assert.match(notice.message, /n.o possui telefone cadastrado/i);
    } finally {
        global.open = originalOpen;
    }
});

test('orcamento sem telefone pode ser marcado quando WhatsApp esta desativado', async () => {
    const ticket = makeTicket({ contact_info: null });
    let updates;
    let openCalls = 0;
    const originalOpen = global.open;
    global.open = () => { openCalls += 1; };

    try {
        await global.AIDATicketActions.sendBudget(ticket, makeBudgetDeps(ticket, {
            isWhatsAppDisabled: () => true,
            mutateTicket: async (_ticket, _action, nextUpdates) => {
                updates = nextUpdates;
                return true;
            }
        }));

        assert.equal(updates.budget_status, 'Enviado');
        assert.equal(openCalls, 0);
    } finally {
        global.open = originalOpen;
    }
});

test('orcamento com telefone valida antes e abre WhatsApp depois de salvar', async () => {
    const ticket = makeTicket();
    const events = [];
    const originalOpen = global.open;
    global.open = (url) => { events.push({ type: 'open', url }); };

    try {
        await global.AIDATicketActions.sendBudget(ticket, makeBudgetDeps(ticket, {
            mutateTicket: async () => {
                events.push({ type: 'mutate' });
                return true;
            }
        }));

        assert.equal(events[0].type, 'mutate');
        assert.equal(events[1].type, 'open');
        assert.match(events[1].url, /^https:\/\/wa\.me\/5511999999999\?text=/);
    } finally {
        global.open = originalOpen;
    }
});

test('painel de agenda guarda contexto explicito da OS e do tecnico', () => {
    const source = fs.readFileSync(path.join(__dirname, '..', 'js', 'main.js'), 'utf8');
    const html = fs.readFileSync(path.join(__dirname, '..', 'app.html'), 'utf8');

    assert.match(source, /openSchedulePanel\(mode, technicianId = null, ticket = null, afterSave = null\)/);
    assert.match(source, /this\.schedulePanelTicket = targetTicket/);
    assert.match(source, /completeBudgetApproval\(/);
    assert.match(html, /x-show="modals\.ticket \|\| schedulePanelOpen"/);
    assert.match(html, /getTechnicianName\(schedulePanelTechnicianId/);
});
