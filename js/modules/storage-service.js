// Storage Service
// Responsável por chamadas ao storage do Supabase, upload de logo, ticket photos, e geração de headers
// Parte da infraestrutura de módulos

window.AIDAStorageService = {
    getStorageHeaders(contentType, deps) {
        const { SUPABASE_KEY, state } = deps;
        const token = state.session?.access_token || SUPABASE_KEY;

        const headers = {
            'apikey': SUPABASE_KEY,
            'Authorization': `Bearer ${token}`,
            'Content-Type': contentType
        };

        // If Employee, send token for RLS derivation
        if (state.employeeSession?.token) {
            headers['x-employee-token'] = state.employeeSession.token;
        }

        return headers;
    },

    async handleLogoUpload(file, deps) {
        const { SUPABASE_URL, SUPABASE_KEY, state } = deps;

        try {
            const url = `${SUPABASE_URL}/functions/v1/upload-workspace-logo`;

            const form = new FormData();
            form.append('file', file);

            const headers = {
                apikey: SUPABASE_KEY
            };

            if (state.session?.access_token) {
                headers['Authorization'] = `Bearer ${state.session.access_token}`;
            }

            if (state.employeeSession?.token) {
                headers['x-employee-token'] = state.employeeSession.token;
            }

            const response = await fetch(url, {
                method: 'POST',
                headers,
                body: form
            });

            if (!response.ok) {
                const txt = await response.text().catch(() => '');
                throw new Error(`Falha no upload (${response.status}): ${txt}`);
            }

            const data = await response.json();
            return data.publicUrl || data.url || data.path;

        } catch(e) {
            throw e;
        }
    },

    async uploadTicketPhoto(file, ticketId, deps) {
        const { SUPABASE_URL, state } = deps;
        try {
            // 1) Path ESTRITO: workspaceId/ticketId/...
            const workspaceId = state.employeeSession?.workspace_id || state.user?.workspace_id;
            if (!workspaceId) throw new Error("Workspace ID not found for upload");

            const safeName = file.name.replace(/[^a-zA-Z0-9.\-_]/g, '_');
            const path = `${workspaceId}/${ticketId}/${Date.now()}_${safeName}`;

            // 2) Upload direto no Storage (sem Edge Function)
            const url = `${SUPABASE_URL}/storage/v1/object/ticket_photos/${path}`;
            const headers = this.getStorageHeaders(file.type, deps); // já injeta x-employee-token quando existir

            const res = await fetch(url, { method: 'POST', headers, body: file });
            if (!res.ok) {
                const txt = await res.text().catch(() => '');
                throw new Error(`Falha no upload (${res.status}): ${txt}`);
            }

            // 3) Retornar APENAS o path (nunca URL pública)
            return path;

        } catch (e) {
            console.error("Upload Error:", e);
            throw e;
        }
    },

    // Helper to resolve view URLs
    async getPhotoUrl(input, deps) {
        const { SUPABASE_URL } = deps;
        if (!input) return '';

        let path = input;

        // 1) Se já é signed (tem token na query), pode retornar direto
        if (typeof path === 'string' && path.startsWith('http') && path.includes('token=')) {
            return path;
        }

        // 2) Se veio URL pública antiga, extrai path
        const pubMarker = '/storage/v1/object/public/ticket_photos/';
        if (path.includes(pubMarker)) {
            path = path.split(pubMarker)[1];
        }

        // 3) Se veio URL privada do storage (object/...), extrai path também
        const objMarker = '/storage/v1/object/ticket_photos/';
        if (path.includes(objMarker)) {
            path = path.split(objMarker)[1];
        }

        // Se ainda for http e não for storage, retorna (ex: imagem externa)
        if (path.startsWith('http')) return path;

        try {
            // Encode path components
            const encodedPath = path.split('/').map(encodeURIComponent).join('/');
            const signEndpoint = `${SUPABASE_URL}/storage/v1/object/sign/ticket_photos/${encodedPath}`;

            const headers = this.getStorageHeaders('application/json', deps);
            const res = await fetch(signEndpoint, {
                method: 'POST',
                headers,
                body: JSON.stringify({ expiresIn: 600 })
            });

            if (!res.ok) {
                const txt = await res.text().catch(() => '');
                console.warn('[SIGN FAIL]', res.status, txt, { input, path });
                return '';
            }

            const data = await res.json();
            const signed = data?.signedURL || data?.signedUrl;
            if (!signed) return '';

            let full;
            if (signed.startsWith('http')) {
                full = signed.includes('/storage/v1/') ? signed : signed.replace(`${SUPABASE_URL}/`, `${SUPABASE_URL}/storage/v1/`);
            } else if (signed.startsWith('/')) {
                full = `${SUPABASE_URL}/storage/v1${signed}`;
            } else {
                full = `${SUPABASE_URL}/storage/v1/${signed}`;
            }

            return full;
        } catch (e) {
            console.warn('Error signing URL:', e, { input, path });
            return '';
        }
    }
};
