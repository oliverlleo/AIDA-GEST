// Ticket Query Service
// Responsável pela montagem e execução das consultas de chamados ao Supabase
// Parte da infraestrutura de módulos

window.AIDATicketQueryService = {
    async fetchTicketsData(deps, loadMore) {
        const { state, supabaseFetch, hasRole } = deps;

        // OPERATIONAL QUEUE RPC
        // Activate only when operational filter is active and we are exactly in the kanban view
        if (state.isKanbanOperationalFilterActive() && state.view === 'kanban') {
            const f = state.kanbanOperationalFilters;
            const limit = state.ticketPagination.limit;
            const offset = state.ticketPagination.page * limit;

            const search = String(f.search || '').trim();

            const payload = {
                p_window: f.window,
                p_basis: f.basis,
                p_status: f.status !== 'all' ? f.status : null,
                p_technician_id: f.technician !== 'all' ? f.technician : null,
                p_search: search ? search : null,
                p_limit: limit,
                p_offset: offset
            };

            const response = await supabaseFetch('rpc/get_operational_queue', 'POST', payload);
            return {
                mode: 'operational_rpc',
                data: response.items || [],
                counts: response.counts || { today: 0, today_tomorrow: 0, next_7_days: 0, overdue: 0, no_deadline: 0, all: 0 }
            };
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
