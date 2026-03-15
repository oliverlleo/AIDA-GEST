// Workspace Config Service
// Responsável por salvar configurações de empresa e tracker
// Parte da infraestrutura de módulos

window.AIDAWorkspaceConfigService = {
    async loadWorkspaceConfig(deps) {
        try {
            let wsData = null;

            // 1. Caminho para Admin Funcionário (usando RPC segura)
            if (deps.state.employeeSession && deps.state.employeeSession.token && deps.state.hasRole('admin')) {
                const rpcData = await deps.supabaseFetch('rpc/get_workspace_company_config_for_employee', 'POST', {
                    p_token: deps.state.employeeSession.token
                });
                if (rpcData && rpcData.length > 0) {
                    wsData = rpcData[0];
                }
            }
            // 2. Caminho preservado para Admin por E-mail (dono)
            else if (deps.state.user?.workspace_id) {
                const data = await deps.supabaseFetch(`workspaces?select=company_code,whatsapp_number,tracker_config&id=eq.${deps.state.user.workspace_id}`);
                if (data && data.length > 0) {
                    wsData = data[0];
                }
            }

            // Aplicar o retorno no estado (comum para os dois caminhos)
            if (wsData) {
                deps.state.companyCode = wsData.company_code;
                deps.state.whatsappNumber = wsData.whatsapp_number || '';

                if (wsData.tracker_config) {
                    deps.state.trackerConfig = {
                        ...deps.state.trackerConfig,
                        ...wsData.tracker_config,
                        colors: {
                            ...deps.state.trackerConfig.colors,
                            ...(wsData.tracker_config.colors || {})
                        },
                        required_ticket_fields: {
                            ...deps.state.trackerConfig.required_ticket_fields,
                            ...(wsData.tracker_config.required_ticket_fields || {})
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
