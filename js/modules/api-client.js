window.AIDAApiClient = {
    async supabaseFetch(deps, endpoint, method = 'GET', body = null) {
        const isRpc = endpoint.startsWith('rpc/');
        const url = `${deps.SUPABASE_URL}/rest/v1/${endpoint}`;

        let token = deps.SUPABASE_KEY;
        if (deps.session && deps.session.access_token) {
            token = deps.session.access_token;
        }

        const headers = {
            'apikey': deps.SUPABASE_KEY,
            'Authorization': `Bearer ${token}`,
            'Content-Type': 'application/json',
            'Prefer': method === 'GET' ? undefined : 'return=representation'
        };

        // Employee Token Header
        if (deps.employeeSession && deps.employeeSession.token) {
            headers['x-employee-token'] = deps.employeeSession.token;
        }

        if (deps.user && deps.user.workspace_id) {
            // If Employee, do NOT send x-workspace-id (Backend derives from Token)
            // If Admin, send it (Admin context uses headers for RLS sometimes, or explicit params)
            // But for safety/compat with new RLS policy, we can send it for Admin.
            // For Employee, strictly omit it to prevent confusion/spoofing, although backend now ignores it.
            if (!deps.employeeSession) {
                headers['x-workspace-id'] = deps.user.workspace_id;
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
    },

    getStorageHeaders(deps, contentType) {
        const token = deps.session?.access_token || deps.SUPABASE_KEY;

        const headers = {
            'apikey': deps.SUPABASE_KEY,
            'Authorization': `Bearer ${token}`,
            'Content-Type': contentType
        };

        // If Employee, send token for RLS derivation
        if (deps.employeeSession?.token) {
            headers['x-employee-token'] = deps.employeeSession.token;
        }

        // Do NOT send x-workspace-id (Removed as per security hardening)
        return headers;
    }
};