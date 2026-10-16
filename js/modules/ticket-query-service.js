// Ticket Query Service
// Responsável pela montagem e execução das consultas de chamados ao Supabase
// Parte da infraestrutura de módulos

window.AIDATicketQueryService = {
    // Rebuild cursors from the first page after an invalidation. Reusing the
    // old last-page cursor would miss records moved by another operator.
    async collectLoadedWindow(fetchPage, targetCount, pageSize = 20) {
        const target = Math.max(pageSize, Number(targetCount) || 0);
        if (target > pageSize * 100) throw new Error('A janela aberta é grande demais para atualizar automaticamente.');
        const items = [], ids = new Set(), cursors = new Set();
        let cursor = null, response = {}, first = {};
        for (let page = 0; page < 100; page++) {
            response = await fetchPage(cursor, page);
            if (page === 0) first = response || {};
            for (const item of response?.items || []) {
                if (!ids.has(item.id)) { ids.add(item.id); items.push(item); }
            }
            const next = response?.next_cursor || null;
            if (!response?.has_more || !next || items.length >= target) break;
            const key = JSON.stringify(next);
            if (cursors.has(key)) throw new Error('Cursor de paginação repetido.');
            cursors.add(key);
            cursor = next;
        }
        return { ...first, items, has_more: Boolean(response?.has_more), next_cursor: response?.next_cursor || null };
    },

    async fetchLoadedTicketsData(deps) {
        const original = deps.state;
        // Filters and cursor inputs must remain those of this request while
        // the user continues navigating. The caller also checks its context.
        const state = Object.assign(Object.create(original), {
            user: { ...original.user },
            adminDashboardFilters: { ...original.adminDashboardFilters },
            kanbanOperationalFilters: { ...original.kanbanOperationalFilters },
            ticketPagination: { ...original.ticketPagination },
            testerBenchPagination: { ...original.testerBenchPagination }
        });
        const snapshotDeps = { ...deps, state };
        if ((state.view === 'kanban' && !state.isKanbanOperationalFilterActive()) || state.view === 'tech_orders') {
            const columns = {};
            await Promise.all(this.getTicketCardStatuses(state).map(async status => {
                const target = original.tickets.filter(ticket => ticket.status === status).length;
                const response = await this.collectLoadedWindow(
                    cursor => deps.supabaseFetch('rpc/get_ticket_cards_page', 'POST', this.buildTicketCardPayload(state, status, cursor)),
                    target, state.ticketCardPageSize
                );
                columns[status] = {
                    items: response.items,
                    total: Number(response.total || 0), hasMore: Boolean(response.has_more), nextCursor: response.next_cursor || null
                };
            }));
            const hydrated = await this.hydrateTickets(snapshotDeps, Object.values(columns).flatMap(column => column.items));
            const byId = new Map(hydrated.map(ticket => [ticket.id, ticket]));
            Object.values(columns).forEach(column => { column.items = column.items.map(ticket => byId.get(ticket.id) || ticket); });
            return { mode: 'ticket_card_pages', columns };
        }
        if (state.view === 'tester_bench' || (state.view === 'kanban' && state.isKanbanOperationalFilterActive())) {
            let firstResult;
            const response = await this.collectLoadedWindow(async (cursor, page) => {
                state.ticketPagination.nextCursor = cursor;
                state.testerBenchPagination.nextCursor = cursor;
                const result = await this.fetchTicketsData(snapshotDeps, page > 0);
                if (!page) firstResult = result;
                return { items: result.data, total: result.total, has_more: result.hasMore, next_cursor: result.nextCursor };
            }, original.tickets.length, state.ticketCardPageSize);
            return { ...firstResult, data: response.items, hasMore: response.has_more, nextCursor: response.next_cursor };
        }
        const items = [], limit = state.ticketPagination.limit;
        const pages = Math.max(1, Math.ceil(original.tickets.length / limit));
        if (pages > 100) throw new Error('A janela aberta é grande demais para atualizar automaticamente.');
        let last = {}, page = 0;
        for (; page < pages; page++) {
            state.ticketPagination.page = page;
            last = await this.fetchTicketsData(snapshotDeps, false);
            if (last.mode !== 'standard') return last;
            items.push(...(last.data || []));
            if ((last.data || []).length < limit) break;
        }
        return { ...last, data: items, loadedPage: Math.min(page, pages - 1), hasMore: (last.data || []).length === limit };
    },

    async hydrateTickets(deps, tickets) {
        const warrantyHydrated = await window.AIDAWarrantyService.hydrateTickets(deps, tickets);
        return await window.AIDAInventoryQueryService.hydrateTickets(deps, warrantyHydrated);
    },
    getTicketCardSortOptions(state) {
        return {
            p_use_priority: state.isPriorityRequestEnabled(),
            p_use_analysis_appointment: state.isModuleEnabled('agenda') && state.isAppointmentTypeEnabled('analysis'),
            p_use_repair_appointment: state.isModuleEnabled('agenda') && state.isAppointmentTypeEnabled('repair'),
            p_use_analysis_deadline: state.isFieldVisible('analysis_deadline'),
            p_use_delivery_deadline: state.isFieldVisible('deadline')
        };
    },

    getTicketCardStatuses(state) {
        if (state.view === 'tech_orders') {
            return state.getTestFlowMode() === 'technician'
                ? ['Analise Tecnica', 'Andamento Reparo', 'Teste Final']
                : ['Analise Tecnica', 'Andamento Reparo'];
        }

        return state.STATUS_COLUMNS.filter(status => {
            if (status === 'Finalizado' && !state.showFinalized) return false;
            if (status === 'Terceirizado' && !state.isOutsourcedEnabled()) return false;
            if (status === 'Teste Final' && state.getTestFlowMode() !== 'kanban') return false;
            return true;
        });
    },

    buildTicketCardPayload(state, status, cursor = null) {
        const isBench = state.view === 'tech_orders';
        const selectedTechnician = isBench && state.hasRole('admin')
            && state.adminDashboardFilters.technician !== 'all'
            ? state.adminDashboardFilters.technician
            : null;

        return {
            p_status: status,
            p_scope: isBench ? 'bench' : 'kanban',
            p_technician_id: selectedTechnician,
            p_search: String(state.searchQuery || '').trim() || null,
            p_limit: state.ticketCardPageSize,
            p_cursor: cursor,
            ...this.getTicketCardSortOptions(state)
        };
    },

    async fetchTicketCardBoardData(deps) {
        const { state, supabaseFetch } = deps;
        const statuses = this.getTicketCardStatuses(state);
        const responses = await Promise.all(statuses.map(async status => {
            const response = await supabaseFetch(
                'rpc/get_ticket_cards_page',
                'POST',
                this.buildTicketCardPayload(state, status)
            );
            return { status, response: response || {} };
        }));
        const allItems = responses.flatMap(({ response }) =>
            Array.isArray(response.items) ? response.items : []
        );
        const hydratedItems = await this.hydrateTickets(deps, allItems);
        const hydratedById = new Map(hydratedItems.map(ticket => [ticket.id, ticket]));

        const columns = {};
        responses.forEach(({ status, response }) => {
            columns[status] = {
                items: (Array.isArray(response.items) ? response.items : [])
                    .map(ticket => hydratedById.get(ticket.id) || ticket),
                total: Number(response.total || 0),
                hasMore: Boolean(response.has_more),
                nextCursor: response.next_cursor || null
            };
        });

        return { mode: 'ticket_card_pages', columns };
    },

    async fetchTicketCardColumnData(deps, status, cursor) {
        const { state, supabaseFetch } = deps;
        const response = await supabaseFetch(
            'rpc/get_ticket_cards_page',
            'POST',
            this.buildTicketCardPayload(state, status, cursor)
        ) || {};
        response.items = await this.hydrateTickets(
            deps,
            Array.isArray(response?.items) ? response.items : []
        );
        return response;
    },

    async fetchTicketDetails(deps, ticketId) {
        const { state, supabaseFetch } = deps;
        const safeId = encodeURIComponent(String(ticketId || ''));
        const safeWorkspaceId = encodeURIComponent(String(state?.user?.workspace_id || ''));
        const rows = await supabaseFetch(`tickets?select=*&id=eq.${safeId}&workspace_id=eq.${safeWorkspaceId}&limit=1`);
        return Array.isArray(rows) && rows.length ? rows[0] : null;
    },

    async fetchTicketsData(deps, loadMore) {
        const { state, supabaseFetch, hasRole } = deps;

        if (state.view === 'tester_bench') {
            const response = await supabaseFetch('rpc/get_test_bench_page', 'POST', {
                p_limit: state.ticketCardPageSize,
                p_cursor: loadMore ? state.testerBenchPagination.nextCursor : null,
                p_use_priority: state.isPriorityRequestEnabled(),
                p_use_delivery_deadline: state.isFieldVisible('deadline')
            });

            return {
                mode: 'test_bench_page',
                data: await this.hydrateTickets(
                    deps,
                    Array.isArray(response?.items) ? response.items : []
                ),
                total: Number(response?.total || 0),
                hasMore: Boolean(response?.has_more),
                nextCursor: response?.next_cursor || null
            };
        }

        // OPERATIONAL FILTER PAGE
        // Activate only when operational filter is active and we are exactly in the kanban view
        if (state.isKanbanOperationalFilterActive() && state.view === 'kanban') {
            const f = state.kanbanOperationalFilters;
            const search = String(f.search || '').trim();

            const payload = {
                p_window: f.window,
                p_basis: state.getEffectiveOperationalBasis(f.basis),
                p_status: f.status !== 'all' ? f.status : null,
                p_technician_id: f.technician !== 'all' ? f.technician : null,
                p_search: search ? search : null,
                p_limit: state.ticketCardPageSize,
                p_cursor: loadMore ? state.ticketPagination.nextCursor : null,
                p_include_counts: !loadMore
            };

            const response = await supabaseFetch('rpc/get_operational_ticket_page', 'POST', payload);
            return {
                mode: 'operational_rpc',
                data: await this.hydrateTickets(deps, response.items || []),
                counts: response.counts || null,
                total: response.total,
                hasMore: Boolean(response.has_more),
                nextCursor: response.next_cursor || null
            };
        }

        // Default boards use bounded, per-column keyset pages. Operational
        // filtering keeps its dedicated RPC because it has different ranking.
        if ((state.view === 'kanban' && !state.isKanbanOperationalFilterActive())
            || state.view === 'tech_orders') {
            return await this.fetchTicketCardBoardData(deps);
        }

        // Base Endpoint with Workspace Filter
        let endpoint = `tickets?select=*&workspace_id=eq.${state.user.workspace_id}&deleted_at=is.null`;

        // SEARCH
        if (state.searchQuery) {
            const q = state.searchQuery;
            const qSafe = encodeURIComponent(`*${q}*`);
            endpoint += `&or=(client_name.ilike.${qSafe},os_number.ilike.${qSafe},device_model.ilike.${qSafe},serial_number.ilike.${qSafe},contact_info.ilike.${qSafe})`;
        }

        // VIEW SPECIFIC LOGIC
        if (state.view === 'kanban' && !state.searchQuery) {
            // KANBAN SPLIT FETCHING
            // 1. Active Tickets (Always fetch up to 200)
            const activeEndpoint = `tickets?select=*&workspace_id=eq.${state.user.workspace_id}&deleted_at=is.null&delivered_at=is.null&order=created_at.desc&limit=200`;
            const activePromise = supabaseFetch(activeEndpoint);

            // 2. Finalized Tickets (If enabled)
            let finalizedPromise = Promise.resolve([]);
            if (state.showFinalized) {
                // Fetch ALL currently loaded finalized tickets to maintain state on refresh
                const totalLimit = (state.finalizedPage + 1) * state.finalizedLimit;
                const finalEndpoint = `tickets?select=*&workspace_id=eq.${state.user.workspace_id}&deleted_at=is.null&delivered_at=not.is.null&order=delivered_at.desc&limit=${totalLimit}`;
                finalizedPromise = supabaseFetch(finalEndpoint);
            }

            const [activeData, finalizedData] = await Promise.all([activePromise, finalizedPromise]);

            let finalizedHasMore = null;
            if (state.showFinalized) {
                finalizedHasMore = (finalizedData && finalizedData.length === state.finalizedLimit);
            }

            return {
                mode: 'kanban',
                data: [...(activeData || []), ...(finalizedData || [])],
                finalizedHasMore
            };

        } else if (state.view === 'tech_orders') {
            // Tech View
            if (hasRole('admin')) {
                const techId = state.adminDashboardFilters.technician;
                if (techId && techId !== 'all') {
                    endpoint += `&technician_id=eq.${techId}`;
                }
            } else if (state.user?.id) {
                 endpoint += `&or=(technician_id.eq.${state.user.id},technician_id.is.null)`;
            }
            if (state.getTestFlowMode && state.getTestFlowMode() === 'technician') {
                endpoint += `&status=in.(Analise Tecnica,Andamento Reparo,Teste Final)`;
            } else {
                endpoint += `&status=in.(Analise Tecnica,Andamento Reparo)`;
            }
            endpoint += `&order=created_at.asc`;
        } else {
            // Dashboard/History/List: Apply Filters & Pagination
            const f = state.adminDashboardFilters;

            if (f.dateStart) endpoint += `&created_at=gte.${f.dateStart}T00:00:00`;
            if (f.dateEnd) endpoint += `&created_at=lte.${f.dateEnd}T23:59:59`;
            if (f.technician !== 'all') endpoint += `&technician_id=eq.${f.technician}`;
            if (f.status !== 'all') endpoint += `&status=eq.${f.status}`;
            if (f.defect !== 'all') endpoint += `&defect_reported=ilike.*${encodeURIComponent(f.defect)}*`;
            if (f.deviceModel !== 'all') endpoint += `&device_model=eq.${encodeURIComponent(f.deviceModel)}`;

            endpoint += `&order=created_at.desc`;

            // PAGINATION
            const limit = state.ticketPagination.limit;
            const offset = state.ticketPagination.page * limit;
            endpoint += `&limit=${limit}&offset=${offset}`;
        }

        const data = await supabaseFetch(endpoint);

        return {
            mode: 'standard',
            data: data
        };
    },

    async fetchFinalizedTicketsData(deps) {
        const { state, supabaseFetch } = deps;
        const offset = state.finalizedPage * state.finalizedLimit;
        const endpoint = `tickets?select=*&workspace_id=eq.${state.user.workspace_id}&deleted_at=is.null&delivered_at=not.is.null&order=delivered_at.desc&limit=${state.finalizedLimit}&offset=${offset}`;

        const data = await supabaseFetch(endpoint);
        return data;
    }
};

