window.AIDAStorageService = {
    async handleLogoUpload(deps, file) {
        if (!file) return null;

        const bucket = 'workspace_logos';
        const path = `${deps.user.workspace_id}/logo/logo_${Date.now()}.png`; // Unique name to force refresh
        const url = `${deps.SUPABASE_URL}/storage/v1/object/${bucket}/${path}`;

        const headers = window.AIDAApiClient.getStorageHeaders(deps, file.type);
        const response = await fetch(url, { method: 'POST', headers, body: file });

        if (!response.ok) throw new Error("Falha no upload");

        // Construct Public URL (bucket is public now)
        const publicUrl = `${deps.SUPABASE_URL}/storage/v1/object/public/${bucket}/${path}`;
        return publicUrl;
    },

    async uploadTicketPhoto(deps, file, ticketId) {
        // 1) Path ESTRITO: workspaceId/ticketId/...
        const workspaceId = deps.employeeSession?.workspace_id || deps.user?.workspace_id;
        if (!workspaceId) throw new Error("Workspace ID not found for upload");

        const safeName = file.name.replace(/[^a-zA-Z0-9.\-_]/g, '_');
        const path = `${workspaceId}/${ticketId}/${Date.now()}_${safeName}`;

        // 2) Upload direto no Storage (sem Edge Function)
        const url = `${deps.SUPABASE_URL}/storage/v1/object/ticket_photos/${path}`;
        const headers = window.AIDAApiClient.getStorageHeaders(deps, file.type); // já injeta x-employee-token quando existir

        const res = await fetch(url, { method: 'POST', headers, body: file });
        if (!res.ok) {
            const txt = await res.text().catch(() => '');
            throw new Error(`Falha no upload (${res.status}): ${txt}`);
        }

        // 3) Retornar APENAS o path (nunca URL pública)
        return path;
    },

    async getPhotoUrl(deps, input) {
        if (!input) return '';

        let path = input;
        console.log('[getPhotoUrl] input:', input);

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
            const signEndpoint = `${deps.SUPABASE_URL}/storage/v1/object/sign/ticket_photos/${encodedPath}`;

            const headers = window.AIDAApiClient.getStorageHeaders(deps, 'application/json');
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
                full = signed.includes('/storage/v1/') ? signed : signed.replace(`${deps.SUPABASE_URL}/`, `${deps.SUPABASE_URL}/storage/v1/`);
            } else if (signed.startsWith('/')) {
                full = `${deps.SUPABASE_URL}/storage/v1${signed}`;
            } else {
                full = `${deps.SUPABASE_URL}/storage/v1/${signed}`;
            }

            console.log('[getPhotoUrl] signed src:', full);
            return full;
        } catch (e) {
            console.warn('Error signing URL:', e, { input, path });
            return '';
        }
    }
};