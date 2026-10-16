const test = require('node:test');
const assert = require('node:assert/strict');
global.window = global;
require('../js/modules/ticket-query-service.js');
const service = global.AIDATicketQueryService;
global.AIDAWarrantyService = { hydrateTickets: async (_deps, tickets) => tickets };
global.AIDAInventoryQueryService = { hydrateTickets: async (_deps, tickets) => tickets };
const items = (prefix, start, count, status) => Array.from({ length: count }, (_, i) => ({ id: `${prefix}-${start + i}`, status }));

test('rebuilds a loaded keyset window from fresh cursors and retains its length', async () => {
    const cursors = [];
    const result = await service.collectLoadedWindow(async cursor => {
        cursors.push(cursor);
        return cursor
            ? { items: items('os', 20, 20), total: 100, has_more: true, next_cursor: 'fresh-40' }
            : { items: items('os', 0, 20), total: 100, has_more: true, next_cursor: 'fresh-20' };
    }, 40, 20);
    assert.deepEqual(cursors, [null, 'fresh-20']);
    assert.equal(result.items.length, 40);
    assert.equal(result.next_cursor, 'fresh-40');
    assert.equal(result.total, 100);
});

test('stops at exhausted pages and rejects repeated cursors or unbounded windows', async () => {
    const result = await service.collectLoadedWindow(async () => ({ items: items('os', 0, 3), has_more: false }), 40);
    assert.equal(result.items.length, 3);
    assert.equal(result.has_more, false);
    await assert.rejects(service.collectLoadedWindow(async () => ({ items: [], has_more: true, next_cursor: 'same' }), 60), /repetido/);
    await assert.rejects(service.collectLoadedWindow(async () => { throw new Error('must not request'); }, 10000), /grande demais/);
});

function state(view = 'kanban') {
    return {
        view, user: { workspace_id: 'company-a' }, searchQuery: 'filtro atual', showFinalized: true,
        STATUS_COLUMNS: ['Analise Tecnica', 'Andamento Reparo'], ticketCardPageSize: 20,
        tickets: [...items('old-a', 0, 40, 'Analise Tecnica'), ...items('old-b', 0, 20, 'Andamento Reparo')],
        adminDashboardFilters: { technician: 'all', status: 'all', deviceModel: 'all', defect: 'all' },
        kanbanOperationalFilters: { window: 'all', basis: 'auto', status: 'all', technician: 'all', search: '' },
        ticketPagination: { page: 2, limit: 20, nextCursor: 'obsolete' }, testerBenchPagination: { nextCursor: 'obsolete-bench' },
        hasRole: () => false, isKanbanOperationalFilterActive: () => false,
        isOutsourcedEnabled: () => true, getTestFlowMode: () => 'kanban',
        isPriorityRequestEnabled: () => true, isModuleEnabled: () => true,
        isAppointmentTypeEnabled: () => true, isFieldVisible: () => true,
        getEffectiveOperationalBasis: basis => basis
    };
}

test('board refresh preserves each loaded column and sends filters through the authorized RPC', async () => {
    const s = state(), requests = [];
    const result = await service.fetchLoadedTicketsData({ state: s, supabaseFetch: async (ep, method, payload) => {
        requests.push({ ep, method, payload });
        const offset = payload.p_cursor ? 20 : 0;
        return { items: items(payload.p_status, offset, 20, payload.p_status), total: 200, has_more: true, next_cursor: `fresh-${offset + 20}` };
    } });
    assert.equal(result.mode, 'ticket_card_pages');
    assert.equal(result.columns['Analise Tecnica'].items.length, 40);
    assert.equal(result.columns['Andamento Reparo'].items.length, 20);
    assert.equal(result.columns['Analise Tecnica'].nextCursor, 'fresh-40');
    assert.equal(s.ticketPagination.page, 2);
    assert.ok(requests.every(r => r.ep === 'rpc/get_ticket_cards_page' && r.method === 'POST'));
    assert.ok(requests.every(r => r.payload.p_search === 'filtro atual' && r.payload.p_limit === 20));
    assert.ok(!requests.some(r => r.payload.p_cursor === 'obsolete'));
});

test('tester refresh retains the loaded window without modifying live cursor inputs', async () => {
    const s = state('tester_bench'); s.tickets = items('old', 0, 40);
    const requests = [];
    const result = await service.fetchLoadedTicketsData({ state: s, supabaseFetch: async (ep, _method, payload) => {
        requests.push({ ep, payload });
        const offset = payload.p_cursor ? 20 : 0;
        return { items: items('fresh', offset, 20), total: 100, has_more: true, next_cursor: `fresh-${offset + 20}` };
    } });
    assert.equal(result.data.length, 40);
    assert.equal(result.nextCursor, 'fresh-40');
    assert.equal(s.testerBenchPagination.nextCursor, 'obsolete-bench');
    assert.deepEqual(requests.map(r => r.payload.p_cursor), [null, 'fresh-20']);
});

test('history refresh retains loaded offset pages instead of resetting to the first page', async () => {
    const s = state('admin_dashboard'); s.tickets = items('old', 0, 40);
    const requests = [];
    const result = await service.fetchLoadedTicketsData({ state: s, supabaseFetch: async endpoint => {
        requests.push(endpoint);
        const offset = Number(new URL(`https://example.test/${endpoint}`).searchParams.get('offset'));
        return items('fresh', offset, 20);
    } });
    assert.equal(result.data.length, 40);
    assert.equal(result.loadedPage, 1);
    assert.equal(result.hasMore, true);
    assert.ok(requests[0].includes('offset=0'));
    assert.ok(requests[1].includes('offset=20'));
    assert.equal(s.ticketPagination.page, 2);
});
