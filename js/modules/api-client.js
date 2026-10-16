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
        const identity = state.session?.user?.id || token;
        const workspace = state.user?.workspace_id;
        const assertCurrentContext = () => {
            if ((state.session?.user?.id || state.session?.access_token) !== identity
                || state.user?.workspace_id !== workspace) {
                const error = new Error('O contexto da conta ou empresa mudou durante a solicitação.');
                error.name = 'AbortError';
                error.contextChanged = true;
                throw error;
            }
        };

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

        if (requestOptions.ticketVersion) {
            const { id, revision } = requestOptions.ticketVersion;
            const normalizedRevision = typeof revision === 'string' && /^[1-9][0-9]*$/.test(revision)
                ? Number(revision) : revision;
            if (typeof id !== 'string' || !id || !Number.isSafeInteger(normalizedRevision) || normalizedRevision < 1) {
                throw new Error('Reabra a OS para carregar sua versão atual antes de salvar.');
            }
            headers['x-aida-ticket-version'] = JSON.stringify({ id, revision: normalizedRevision });
        }
        if (requestOptions.operationVersion) {
            const { resource, id, revision } = requestOptions.operationVersion;
            const normalizedRevision = typeof revision === 'string' && /^[1-9][0-9]*$/.test(revision)
                ? Number(revision) : revision;
            if (!['inventory_purchases', 'ticket_appointments'].includes(resource)
                || typeof id !== 'string' || !id || !Number.isSafeInteger(normalizedRevision) || normalizedRevision < 1) {
                throw new Error('Reabra esta operação para revisar sua versão atual antes de salvar.');
            }
            headers['x-aida-operation-version'] = JSON.stringify({ resource, id, revision: normalizedRevision });
        }

        const options = {
            method,
            headers,
            body: body ? JSON.stringify(body) : undefined
        };

        const controller = new AbortController();
        options.signal = controller.signal;
        const deadline = setTimeout(() => controller.abort(), 30000);
        try {
            const response = await fetch(url, options);
            assertCurrentContext();

            if (!response.ok) {
                const error = await this.readApiError(response);
                assertCurrentContext();
                throw error;
            }

            if (response.status === 204 || requestOptions.returnRepresentation === false) return null;

            const result = await response.json();
            assertCurrentContext();
            return result;
        } catch (error) {
            if (controller.signal.aborted) {
                const timeoutError = new Error(method === 'GET' || method === 'HEAD'
                    ? 'A consulta demorou demais. Tente atualizar novamente.'
                    : 'O servidor demorou para responder. Consulte o estado atual antes de repetir a operação.');
                timeoutError.code = 'AIDA_TIMEOUT';
                timeoutError.unknownCommit = method !== 'GET' && method !== 'HEAD';
                throw timeoutError;
            }
            throw error;
        } finally {
            clearTimeout(deadline);
        }
    }
};
