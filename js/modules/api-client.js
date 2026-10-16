// API Client Service
// Responsável pelas chamadas REST/RPC para o Supabase
// Parte da infraestrutura de módulos

window.AIDAApiClient = {
    getRetryAfter(response, fallbackSeconds = 60, now = Date.now()) {
        const value = response?.headers?.get?.('Retry-After');
        if (value != null && String(value).trim() !== '') {
            const normalized = String(value).trim();
            if (/^\d+(?:\.\d+)?$/.test(normalized)) {
                const seconds = Number(normalized);
                if (Number.isFinite(seconds)) return Math.max(1, Math.ceil(seconds));
            }
            const date = Date.parse(normalized);
            if (Number.isFinite(date)) return Math.max(1, Math.ceil((date - now) / 1000));
        }
        return fallbackSeconds;
    },

    createApiError(response, payload = {}) {
        const status = Number(response?.status || 0);
        const data = payload && typeof payload === 'object' ? payload : {};
        let message = typeof data.message === 'string' && data.message
            ? data.message : `Não foi possível concluir a operação (${status}).`;
        let retryAfter;
        if (status === 429) {
            retryAfter = this.getRetryAfter(response);
            message = `Muitas solicitações em pouco tempo. Aguarde ${retryAfter} segundos e tente novamente.`;
        } else if (status === 413) {
            message = 'O arquivo ou a solicitação ultrapassa o tamanho permitido.';
        } else if (status === 415) {
            message = 'Este formato de arquivo não é permitido.';
        }
        const error = new Error(message);
        error.status = status;
        error.code = data.code || data.error_code;
        if (retryAfter !== undefined) error.retryAfter = retryAfter;
        return error;
    },

    async readApiError(response) {
        let payload;
        try { payload = await response.json(); } catch (_) { payload = {}; }
        return this.createApiError(response, payload);
    },

    async supabaseFetch(endpoint, method = 'GET', body = null, deps, requestOptions = {}) {
        const { SUPABASE_URL, SUPABASE_KEY, state } = deps;

        const url = `${SUPABASE_URL}/rest/v1/${endpoint}`;

        const token = state.session?.access_token;
        if (!token) throw new Error('Entre na sua conta para continuar.');

        const returnPreference = requestOptions.returnRepresentation === false ? 'return=minimal' : 'return=representation';
        const headers = {
            'apikey': SUPABASE_KEY,
            'Authorization': `Bearer ${token}`,
            'Content-Type': 'application/json',
            'Prefer': method === 'GET'
                ? undefined
                : (method === 'POST' && requestOptions.upsert === true
                    ? `resolution=merge-duplicates,${returnPreference}`
                    : returnPreference)
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
            throw await this.readApiError(response);
        }

        if (response.status === 204 || requestOptions.returnRepresentation === false) return null;

        return await response.json();
    }
};
