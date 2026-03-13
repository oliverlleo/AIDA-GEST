// Recycle Bin Service
// Responsável por gerenciar itens apagados temporariamente (Lixeira)
// Parte da infraestrutura de módulos

window.AIDARecycleBinService = {
    async fetchDeletedItems(deps) {
        const { state, supabaseFetch, hasRole, setLoading, notify } = deps;
        if (!state.user?.workspace_id || !hasRole('admin')) return;

        setLoading(true);
        try {
            const tickets = await supabaseFetch(
                `tickets?select=*&workspace_id=eq.${state.user.workspace_id}&deleted_at=not.is.null&order=deleted_at.desc`
            );
            state.deletedTickets = tickets || [];

            const emps = await supabaseFetch(
                `employees?select=*&workspace_id=eq.${state.user.workspace_id}&deleted_at=not.is.null&order=deleted_at.desc`
            );
            state.deletedEmployees = emps || [];

        } catch(e) {
            notify("Erro ao buscar lixeira: " + e.message, "error");
        } finally {
            setLoading(false);
        }
    },

    async restoreItem(type, id, deps) {
        const { state, supabaseFetch, mutateTicket, fetchDeletedItems, fetchEmployees, notify, setLoading } = deps;

        if (!confirm("Deseja restaurar este item?")) return;

        if (type === 'ticket') {
            const ticketToRestore = state.deletedTickets.find(t => t.id === id) || { id };
            const actionLog = {
                action: 'Restaurou Chamado',
                details: `Chamado restaurado da lixeira por ${state.user.name}.`
            };

            await mutateTicket(ticketToRestore, 'restoreItem', {
                deleted_at: null
            }, actionLog, { showNotify: true, notifyMessage: "Item restaurado!", fetchTickets: true });

            await fetchDeletedItems();
            return;
        }

        setLoading(true);
        try {
            await supabaseFetch(`employees?id=eq.${id}`, 'PATCH', {
                deleted_at: null
            });
            notify("Item restaurado!");

            await fetchDeletedItems();
            await fetchEmployees();

        } catch(e) {
            notify("Erro ao restaurar: " + e.message, "error");
        } finally {
            setLoading(false);
        }
    }
};
