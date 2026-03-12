// Logs and Notifications Service
// Responsável por ler e gravar logs e notificações
// Parte da infraestrutura de módulos

window.AIDALogsNotificationsService = {
    async logTicketAction(ticketId, action, details = null, deps) {
        const { state, supabaseFetch, fetchGlobalLogs } = deps;
        try {
            await supabaseFetch('ticket_logs', 'POST', {
                ticket_id: ticketId,
                action: action,
                details: details,
                user_name: state.user.name
            });
            if (state.view === 'dashboard') fetchGlobalLogs();
        } catch (e) {
            console.error("Log failed:", e);
        }
    },

    async fetchTicketLogs(ticketId, deps) {
        const { hasRole, supabaseFetch } = deps;
        if (!hasRole('admin')) return [];
        try {
            const logs = await supabaseFetch(`ticket_logs?ticket_id=eq.${ticketId}&order=created_at.desc`);
            return logs || [];
        } catch (e) {
            console.error("Fetch logs failed:", e);
            return [];
        }
    },

    async fetchGlobalLogs(deps) {
        const { state, supabaseFetch } = deps;
        if (!state.user?.workspace_id) return;
        try {
            const logs = await supabaseFetch(`ticket_logs?select=*,tickets(os_number,client_name,device_model)&order=created_at.desc&limit=10`);
            state.dashboardLogs = logs || [];
        } catch (e) {
            console.error("Fetch global logs failed:", e);
        }
    },

    async fetchNotifications(deps) {
        const { state, supabaseFetch } = deps;
        if (!state.user) return;
        try {
            let query = `notifications?select=*,tickets(os_number,device_model)&order=created_at.desc&limit=50`;
            const data = await supabaseFetch(query);

            if (data) {
                const myRoles = state.user.roles || [];
                const userId = state.user.id;

                state.notificationsList = data.filter(n => {
                    if (n.recipient_user_id) return n.recipient_user_id === userId;
                    if (n.recipient_role) return myRoles.includes(n.recipient_role);
                    return false;
                });
            }
        } catch(e) {
            console.error("Fetch Notif Error:", e);
        }
    },

    async createNotification(data, deps) {
        const { supabaseFetch } = deps;
        try {
            await supabaseFetch('notifications', 'POST', data);
        } catch(e) { console.error("Create Notif Error:", e); }
    },

    async markNotificationRead(id, deps) {
        const { state, supabaseFetch } = deps;
        try {
            const n = state.notificationsList.find(x => x.id === id);
            if (n) n.is_read = true;

            await supabaseFetch(`notifications?id=eq.${id}`, 'PATCH', { is_read: true, read_at: new Date().toISOString() });
        } catch(e) { console.error(e); }
    },

    async markAllRead(deps) {
        const { state, supabaseFetch } = deps;
        const unreadIds = state.notificationsList.filter(n => !n.is_read).map(n => n.id);
        if (unreadIds.length === 0) return;

        state.notificationsList.forEach(n => n.is_read = true);
        await supabaseFetch(`notifications?id=in.(${unreadIds.join(',')})`, 'PATCH', { is_read: true, read_at: new Date().toISOString() });
    }
};
