// API Client Service
// Responsável pelas chamadas REST/RPC para o Supabase
// Parte da infraestrutura de módulos

window.AIDAApiClient = {
    async supabaseFetch(endpoint, method = 'GET', body = null, deps, requestOptions = {}) {
        const { SUPABASE_URL, SUPABASE_KEY, state } = deps;

        const url = `${SUPABASE_URL}/rest/v1/${endpoint}`;

        const token = state.session?.access_token;
        if (!token) throw new Error('Entre na sua conta para continuar.');

        const headers = {
            'apikey': SUPABASE_KEY,
            'Authorization': `Bearer ${token}`,
            'Content-Type': 'application/json',
            'Prefer': method === 'GET'
                ? undefined
                : (requestOptions.returnRepresentation === false ? 'return=minimal' : 'return=representation')
        };

        // Context is only a request; the server validates this membership for every operation.
        if (state.user?.workspace_id) headers['x-workspace-id'] = state.user.workspace_id;

        const options = {
            method,
            headers,
            body: body ? JSON.stringify(body) : undefined
        };

        const response = await fetch(url, options);

        if (!response.ok) {
            const errorData = await response.json().catch(() => ({ message: response.statusText }));
            const error = new Error(errorData.message || `Error ${response.status}: ${response.statusText}`);
            error.status = response.status;
            error.code = errorData.code;
            throw error;
        }

        if (response.status === 204 || requestOptions.returnRepresentation === false) return null;

        return await response.json();
    }
};
