// API Client Service
// Responsável pelas chamadas REST/RPC para o Supabase
// Parte da infraestrutura de módulos

window.AIDAApiClient = {
    async supabaseFetch(endpoint, method = 'GET', body = null, deps) {
        const { SUPABASE_URL, SUPABASE_KEY, state } = deps;

        const url = `${SUPABASE_URL}/rest/v1/${endpoint}`;

        let token = SUPABASE_KEY;
        if (state.session && state.session.access_token) {
            token = state.session.access_token;
        }

        const headers = {
            'apikey': SUPABASE_KEY,
            'Authorization': `Bearer ${token}`,
            'Content-Type': 'application/json',
            'Prefer': method === 'GET' ? undefined : 'return=representation'
        };

        // Employee Token Header
        if (state.employeeSession && state.employeeSession.token) {
            headers['x-employee-token'] = state.employeeSession.token;
        }

        if (state.user && state.user.workspace_id) {
            // If Employee, do NOT send x-workspace-id (Backend derives from Token)
            // If Admin, send it (Admin context uses headers for RLS sometimes, or explicit params)
            if (!state.employeeSession) {
                headers['x-workspace-id'] = state.user.workspace_id;
            }
        }

        const options = {
            method,
            headers,
            body: body ? JSON.stringify(body) : undefined
        };

        const response = await fetch(url, options);

        if (!response.ok) {
            const errorData = await response.json().catch(() => ({ message: response.statusText }));
            throw new Error(errorData.message || `Error ${response.status}: ${response.statusText}`);
        }

        if (response.status === 204) return null;

        return await response.json();
    }
};
