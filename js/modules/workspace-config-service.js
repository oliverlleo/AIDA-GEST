// Workspace Config Service
// Responsável por salvar configurações de empresa e tracker
// Parte da infraestrutura de módulos

window.AIDAWorkspaceConfigService = {
    async saveCompanyConfig(deps) {
        if (!deps.state.user?.workspace_id || !deps.state.hasRole('admin')) return;
        deps.setLoading(true);
        try {
            await deps.supabaseFetch('rpc/update_workspace_company_config', 'POST', { p_whatsapp_number: deps.state.whatsappNumber });
            deps.notify("Configurações salvas!");
        } catch (e) {
            deps.notify("Erro ao salvar: " + e.message, "error");
        } finally {
            deps.setLoading(false);
        }
    },

    async saveTrackerConfig(deps) {
        if (!deps.state.user?.workspace_id || !deps.state.hasRole('admin')) return;
        deps.setLoading(true);
        try {
            const res = await deps.supabaseFetch('rpc/update_workspace_tracker_config', 'POST', { p_config: deps.state.trackerConfig });

            // Check if update actually happened
            // Since it's an RPC, it throws if not found/unauthorized, so success implies it worked

            if (deps.state.view === 'management_settings') {
                deps.notify("Configurações de Gerenciamento salvas!");
            } else {
                deps.notify("Configurações de Acompanhamento salvas!");
            }

            // Refresh data to apply new flow rules (e.g. Tech Bench tickets)
            await deps.fetchTickets();
        } catch (e) {
            deps.notify("Erro ao salvar: " + e.message, "error");
        } finally {
            deps.setLoading(false);
        }
    }
};
