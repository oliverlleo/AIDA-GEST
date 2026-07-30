const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const main = fs.readFileSync(path.join(root, 'js', 'main.js'), 'utf8');

global.window = global;
require('../js/modules/ticket-context.js');

test('modal ticket wins over a stale or reduced card with the same id', () => {
    const card = { id: 'os-1', status: 'Aprovacao', _card_summary: true };
    const modalTicket = { id: 'os-1', status: 'Compra Peca', budget_status: 'Aprovado' };

    const resolved = global.AIDATicketContext.resolveTicket('os-1', [card], modalTicket);

    assert.equal(resolved, modalTicket);
    assert.equal(resolved.status, 'Compra Peca');
    assert.equal(resolved.budget_status, 'Aprovado');
});

test('card remains the source when the open modal belongs to another OS', () => {
    const card = { id: 'os-1', status: 'Aprovacao' };
    const otherModal = { id: 'os-2', status: 'Analise Tecnica' };

    assert.equal(global.AIDATicketContext.resolveTicket('os-1', [card], otherModal), card);
});

test('post-mutation refresh rehydrates only the open OS and ignores stale responses', () => {
    assert.match(main, /refreshPostMutation\(forceListRefetch = false\)[\s\S]*refreshOpenTicketModal\(this\.selectedTicket\.id\)/);
    assert.match(main, /refreshOpenTicketModal\(ticketId = this\.selectedTicket\?\.id\)[\s\S]*fetchTicketDetails/);
    assert.match(main, /requestId !== this\.ticketModalRefreshRequestId[\s\S]*this\.selectedTicket\?\.id !== ticketId/);
    assert.match(main, /inventory_summary: inventorySummary/);
    assert.match(main, /this\.selectedTicket = hydratedTicket/);
    assert.match(main, /fetchTicketAppointments\(ticketId\)/);
    assert.doesNotMatch(main, /refreshOpenTicketModal\([^)]*workspace/i);
});
