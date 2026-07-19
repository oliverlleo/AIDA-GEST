const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

global.window = global;
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
