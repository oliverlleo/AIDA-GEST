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

};
