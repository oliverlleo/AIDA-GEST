// Dashboard Service
// Responsável por buscar métricas, relatórios diários e alertas operacionais para os dashboards
// Parte da infraestrutura de módulos

window.AIDADashboardService = {
    async requestDashboardMetrics(params, deps) {
        const { supabaseFetch } = deps;
        try {
            const data = await supabaseFetch('rpc/get_dashboard_kpis', 'POST', params);
            return data;
        } catch (e) {
            console.error("Dashboard RPC Error:", e);
            throw e;
        }
    },

    async fetchOperationalAlerts(deps) {
        const { state, supabaseFetch } = deps;
        if (!state.user?.workspace_id) return null;
        try {
            const data = await supabaseFetch('rpc/get_operational_alerts', 'POST', {
                p_workspace_id: state.user.workspace_id
            });
            return data;
        } catch (e) {
            console.error("Fetch Alerts Error:", e);
            return null;
        }
    },

    async requestDailyReport(params, deps) {
        const { supabaseFetch } = deps;
        try {
            const data = await supabaseFetch('rpc/get_daily_report', 'POST', params);
            return data;
        } catch (e) {
            console.error("Daily Report Error:", e);
            throw e;
        }
    }
};
