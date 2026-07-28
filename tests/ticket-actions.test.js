const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

global.window = global;
require('../js/modules/warranty-service.js');
require('../js/modules/ticket-actions.js');

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
    const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');

    assert.match(source, /openSchedulePanel\(mode, technicianId = null, ticket = null, afterSave = null\)/);
    assert.match(source, /this\.schedulePanelTicket = targetTicket/);
    assert.match(source, /const targetTicket = this\.schedulePanelTicket/);
    assert.match(source, /completeBudgetApproval\(/);
    assert.match(html, /x-show="modals\.ticket \|\| schedulePanelOpen"/);
    assert.match(html, /getTechnicianName\(schedulePanelTechnicianId/);
});
