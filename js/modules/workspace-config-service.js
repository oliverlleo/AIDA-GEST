// Workspace Config Service
// Responsável por salvar configurações de empresa e tracker
// Parte da infraestrutura de módulos

window.AIDAWorkspaceConfigService = {
    async loadWorkspaceConfig(deps) {
        const workspaceId = deps.state.user?.workspace_id || deps.state.employeeSession?.workspace_id;
        if (!workspaceId) return;

        try {
            // Re-fetch essential workspace details (e.g., whatsapp_number, company_code)
            // Note: Since RLS policies generally allow users in the same workspace to select,
            // a direct fetch on `workspaces` table via the `workspace_id` is safe and effective.
            const data = await deps.supabaseFetch(`workspaces?select=company_code,whatsapp_number,tracker_config&id=eq.${workspaceId}`);

            if (data && data.length > 0) {
                const ws = data[0];
                deps.state.companyCode = ws.company_code;
                deps.state.whatsappNumber = ws.whatsapp_number || '';

                if (ws.tracker_config) {
                    deps.state.trackerConfig = {
                        ...deps.state.trackerConfig,
                        ...ws.tracker_config,
                        colors: {
                            ...deps.state.trackerConfig.colors,
                            ...(ws.tracker_config.colors || {})
                        },
                        required_ticket_fields: {
                            ...deps.state.trackerConfig.required_ticket_fields,
                            ...(ws.tracker_config.required_ticket_fields || {})
                        }
                    };
                }
            }
        } catch (e) {
            console.error("Erro ao recarregar configurações do workspace:", e);
        }
    },

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
