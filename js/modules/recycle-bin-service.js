// Recycle Bin Service
// Responsável por gerenciar itens apagados temporariamente (Lixeira)
// Parte da infraestrutura de módulos

window.AIDARecycleBinService = {
    SAFE_EMPLOYEE_FIELDS: 'id,workspace_id,name,username,roles,created_at,deleted_at,must_change_password',

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
                `employees?select=${this.SAFE_EMPLOYEE_FIELDS}&workspace_id=eq.${state.user.workspace_id}&deleted_at=not.is.null&order=deleted_at.desc`
            );
            state.deletedEmployees = emps || [];

        } catch(e) {
            notify("Erro ao buscar lixeira: " + e.message, "error");
        } finally {
            setLoading(false);
        }
    },

};
