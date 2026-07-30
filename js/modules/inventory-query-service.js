(function () {
    function emptyPage() {
        return { items: [], has_more: false, next_cursor: null };
    }

    window.AIDAInventoryQueryService = {
        async fetchDashboard(deps) {
            const data = await deps.supabaseFetch('rpc/get_inventory_dashboard', 'POST', {});
            return {
                active_items: Number(data?.active_items || 0),
                tracked_items: Number(data?.tracked_items || 0),
                low_stock_items: Number(data?.low_stock_items || 0),
                out_of_stock_items: Number(data?.out_of_stock_items || 0),
                estimated_stock_value: Number(data?.estimated_stock_value || 0),
                open_purchases: Number(data?.open_purchases || 0),
                pending_ticket_parts: Number(data?.pending_ticket_parts || 0)
            };
        },

        async fetchItems(deps, options = {}) {
            const response = await deps.supabaseFetch('rpc/get_inventory_items_page', 'POST', {
                p_search: String(options.search || '').trim() || null,
                p_category: options.category && options.category !== 'all'
                    ? options.category
                    : null,
                p_stock_filter: options.stockFilter || 'all',
                p_limit: Math.min(50, Math.max(1, Number(options.limit || 25))),
                p_cursor: options.cursor || null
            });
            return response || emptyPage();
        },

        async hydrateTickets(deps, tickets) {
            const items = Array.isArray(tickets) ? tickets : [];
            if (!deps.state?.isInventoryEnabled?.() || !items.length) return items;
            const ids = [...new Set(items.map(ticket => ticket?.id).filter(Boolean))];
            const responses = [];
            for (let index = 0; index < ids.length; index += 100) {
                responses.push(await deps.supabaseFetch('rpc/get_ticket_inventory_summaries', 'POST', {
                    p_ticket_ids: ids.slice(index, index + 100)
                }));
            }
            const byId = new Map(responses.flatMap(response => Array.isArray(response) ? response : []).map(row => [row.id, row.inventory_summary]));
            let hydrated = items.map(ticket => byId.has(ticket.id)
                ? { ...ticket, inventory_summary: byId.get(ticket.id) }
                : ticket);

            const canViewCosts = deps.state.hasRole?.('admin') || deps.state.hasRole?.('atendente');
            const budgetIds = [...new Set(
                hydrated
                    .filter(ticket => ticket?.status === 'Aprovacao')
                    .map(ticket => ticket?.id)
                    .filter(Boolean)
            )];
            if (!canViewCosts || !budgetIds.length) return hydrated;

            const costResponses = [];
            for (let index = 0; index < budgetIds.length; index += 100) {
                costResponses.push(await deps.supabaseFetch('rpc/get_ticket_inventory_budget_cost_summaries', 'POST', {
                    p_ticket_ids: budgetIds.slice(index, index + 100)
                }));
            }
            const costsById = new Map(
                costResponses
                    .flatMap(response => Array.isArray(response) ? response : [])
                    .map(row => [row.id, row.inventory_cost_summary])
            );
            hydrated = hydrated.map(ticket => costsById.has(ticket.id)
                ? { ...ticket, inventory_cost_summary: costsById.get(ticket.id) }
                : ticket);
            return hydrated;
        },
        async fetchCreationCatalog(deps, deviceModel, options = {}) {
            const response = await deps.supabaseFetch('rpc/get_inventory_creation_catalog_page', 'POST', {
                p_device_model: String(deviceModel || '').trim() || null,
                p_search: String(options.search || '').trim() || null,
                p_limit: Math.min(50, Math.max(1, Number(options.limit || 20))),
                p_cursor: options.cursor || null
            });
            return response || emptyPage();
        },

        async fetchCatalog(deps, ticketId, options = {}) {
            const response = await deps.supabaseFetch('rpc/get_inventory_catalog_page', 'POST', {
                p_ticket_id: ticketId,
                p_search: String(options.search || '').trim() || null,
                p_limit: Math.min(50, Math.max(1, Number(options.limit || 20))),
                p_cursor: options.cursor || null
            });
            return response || emptyPage();
        }
    };
})();
