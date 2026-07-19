const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

global.window = global;
require('../js/modules/ticket-actions.js');

test('aprovar orçamento abre agenda de reparo com o técnico da OS', async () => {
    const ticket = {
        id: 'ticket-id',
        technician_id: 'technician-id',
        parts_needed: null,
        repair_scheduled: false
    };
    let scheduleArgs;

    await global.AIDATicketActions.approveRepair(ticket, {
        resolveTicket: () => ticket,
        isPartsControlEnabled: () => false,
        isAppointmentTypeEnabled: () => true,
        getLogContext: () => ({ client: 'Cliente', device: 'Aparelho' }),
        updateStatus: async () => true,
        state: {
            openSchedulePanel: (...args) => {
                scheduleArgs = args;
            }
        }
    });

    assert.deepEqual(scheduleArgs, ['repair', 'technician-id']);
});

test('painel de agenda prioriza o técnico informado pelo fluxo', () => {
    const source = fs.readFileSync(path.join(__dirname, '..', 'js', 'main.js'), 'utf8');

    assert.match(source, /openSchedulePanel\(mode, technicianId = null\)/);
    assert.match(
        source,
        /const targetTechId = technicianId \|\| \(this\.modals\.viewTicket \? this\.selectedTicket\?\.technician_id : this\.ticketForm\.technician_id\)/
    );
});
