// Storage Service
// Responsável por chamadas ao storage do Supabase, upload de logo, ticket photos, e geração de headers
// Parte da infraestrutura de módulos

window.AIDAStorageService = {
    localPhotoPreviews: new Map(),

    validateImage(file, maxBytes, allowedTypes = null) {
        if (!file || !Number.isSafeInteger(file.size) || file.size < 1) throw new Error('Selecione uma imagem válida.');
        if (file.size > maxBytes) throw new Error(`A imagem deve ter no máximo ${maxBytes / 1048576} MB.`);
        let type = String(file.type || '').trim().toLowerCase();
        if (!type) {
            const extension = String(file.name || '').toLowerCase().split('.').pop();
            const imageTypes = {
                jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', webp: 'image/webp',
                gif: 'image/gif', heic: 'image/heic', heif: 'image/heif',
                avif: 'image/avif', bmp: 'image/bmp', tif: 'image/tiff', tiff: 'image/tiff'
            };
            type = imageTypes[extension] || '';
        }
        if (!/^image\/[a-z0-9.+-]+$/.test(type) || (allowedTypes && !allowedTypes.includes(type))) {
            throw new Error(allowedTypes ? 'Use uma imagem no formato permitido.' : 'Selecione um arquivo de imagem.');
        }
        return type;
    },

    async reserveStorageUpload(bucket, path, file, mimeType, deps) {
        const payload = { p_bucket_id: bucket, p_path: path, p_size: file.size, p_mime_type: mimeType };
        const reservation = deps.supabaseFetch
            ? await deps.supabaseFetch('rpc/reserve_storage_upload', 'POST', payload)
            : await window.AIDAApiClient.supabaseFetch('rpc/reserve_storage_upload', 'POST', payload, deps);
        if (reservation?.reserved === false || reservation?.success === false) {
            throw new Error('Não foi possível autorizar o envio. Tente novamente.');
        }
        return reservation;
    },

    rememberLocalPhotoPreview(path, file) {
        if (!path || !file || typeof URL?.createObjectURL !== 'function') return;
        this.forgetLocalPhotoPreview(path);
        this.localPhotoPreviews.set(path, URL.createObjectURL(file));
    },

    forgetLocalPhotoPreview(path) {
        const previewUrl = this.localPhotoPreviews.get(path);
        if (!previewUrl) return;
        if (typeof URL?.revokeObjectURL === 'function') URL.revokeObjectURL(previewUrl);
        this.localPhotoPreviews.delete(path);
    },

    clearLocalPhotoPreviews() {
        for (const path of Array.from(this.localPhotoPreviews.keys())) {
            this.forgetLocalPhotoPreview(path);
        }
    },

    getStorageHeaders(contentType, deps) {
        const { SUPABASE_KEY, state } = deps;
        const token = state.session?.access_token;
        if (!token || !state.user?.workspace_id) throw new Error('Entre em uma empresa para acessar arquivos.');

        const headers = {
            'apikey': SUPABASE_KEY,
            'Authorization': `Bearer ${token}`,
            'Content-Type': contentType,
            'x-workspace-id': state.user.workspace_id
        };

        return headers;
    },

    async handleLogoUpload(file, deps) {
        const { SUPABASE_URL, SUPABASE_KEY, state } = deps;

        try {
            const mimeType = this.validateImage(file, 5242880, ['image/jpeg', 'image/png', 'image/webp', 'image/gif']);
            const url = `${SUPABASE_URL}/functions/v1/upload-workspace-logo`;

            const form = new FormData();
            form.append('file', file.type === mimeType ? file : file.slice(0, file.size, mimeType), file.name || 'logo');

            const headers = this.getStorageHeaders('application/octet-stream', deps);
            delete headers['Content-Type']; // The browser supplies the multipart boundary.
            form.append('workspace_id', state.user.workspace_id);

            const response = await fetch(url, {
                method: 'POST',
                headers,
                body: form
            });

            if (!response.ok) {
                throw await window.AIDAApiClient.readApiError(response);
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
            const mimeType = this.validateImage(file, 20971520);
            // 1) Path ESTRITO: workspaceId/ticketId/...
            const workspaceId = state.user?.workspace_id;
            if (!workspaceId) throw new Error("Workspace ID not found for upload");

            const safeName = String(file.name || 'imagem').replace(/[^a-zA-Z0-9.\-_]/g, '_');
            const path = `${workspaceId}/${ticketId}/${Date.now()}_${safeName}`;

            // 2) Upload direto no Storage (sem Edge Function)
            const url = `${SUPABASE_URL}/storage/v1/object/ticket_photos/${path}`;
            const headers = this.getStorageHeaders(mimeType, deps);

            await this.reserveStorageUpload('ticket_photos', path, file, mimeType, deps);
            const res = await fetch(url, { method: 'POST', headers, body: file });
            if (!res.ok) {
                throw await window.AIDAApiClient.readApiError(res);
            }

            // A nova OS ainda nao existe no banco neste momento. Guardar uma
            // miniatura local evita assinar um objeto que a RLS so liberara
            // depois da criacao, sem tornar o bucket publico.
            this.rememberLocalPhotoPreview(path, file);

            // 3) Retornar APENAS o path (nunca URL pública)
            return path;

        } catch (e) {
            console.error("Upload Error:", e);
            throw e;
        }
    },

    // Helper to resolve view URLs
    async uploadInventoryImage(file, itemId, deps) {
        const { SUPABASE_URL } = deps;
        const workspaceId = deps.state.user?.workspace_id;
        if (!workspaceId || !itemId) throw new Error('Empresa ou item não identificado.');
        const mimeType = this.validateImage(file, 5242880, ['image/jpeg','image/png','image/webp']);
        const safeName = String(file.name || 'imagem').replace(/[^a-zA-Z0-9.\-_]/g, '_');
        const path = `${workspaceId}/inventory/${itemId}/${Date.now()}_${safeName}`;
        const encodedPath = path.split('/').map(encodeURIComponent).join('/');
        const headers = this.getStorageHeaders(mimeType, deps);
        await this.reserveStorageUpload('inventory_images', path, file, mimeType, deps);
        const res = await fetch(`${SUPABASE_URL}/storage/v1/object/inventory_images/${encodedPath}`, {
            method: 'POST', headers, body: file
        });
        if (!res.ok) {
            throw await window.AIDAApiClient.readApiError(res);
        }
        return path;
    },

    async getInventoryImageUrl(path, deps) {
        const { SUPABASE_URL } = deps;
        if (!path) return '';
        if (path.startsWith('http')) return path;
        const encodedPath = path.split('/').map(encodeURIComponent).join('/');
        const res = await fetch(`${SUPABASE_URL}/storage/v1/object/sign/inventory_images/${encodedPath}`, {
            method: 'POST', headers: this.getStorageHeaders('application/json', deps),
            body: JSON.stringify({ expiresIn: 600 })
        });
        if (!res.ok) return '';
        const data = await res.json();
        const signed = data?.signedURL || data?.signedUrl;
        if (!signed) return '';
        if (signed.startsWith('http')) return signed;
        return `${SUPABASE_URL}/storage/v1${signed.startsWith('/') ? signed : `/${signed}`}`;
    },

    async deleteInventoryImage(path, deps) {
        const { SUPABASE_URL } = deps;
        if (!path || path.startsWith('http')) return;
        const encodedPath = path.split('/').map(encodeURIComponent).join('/');
        const res = await fetch(`${SUPABASE_URL}/storage/v1/object/inventory_images/${encodedPath}`, {
            method: 'DELETE', headers: this.getStorageHeaders('application/json', deps)
        });
        if (!res.ok && res.status !== 404) {
            throw await window.AIDAApiClient.readApiError(res);
        }
    },

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

        // Enquanto o cadastro ainda nao criou a OS, use o proprio arquivo
        // selecionado no navegador para a miniatura.
        const localPreview = this.localPhotoPreviews.get(path);
        if (localPreview) return localPreview;

        try {
            // Encode path components
            const encodedPath = path.split('/').map(encodeURIComponent).join('/');
            const signEndpoint = `${SUPABASE_URL}/storage/v1/object/sign/ticket_photos/${encodedPath}`;

            const headers = this.getStorageHeaders('application/json', deps);
            const retryDelays = [0, 200, 500, 1000];
            let res;

            // Logo depois do upload, o Storage pode responder 404 por alguns
            // milissegundos enquanto o objeto termina de ficar disponivel para
            // a assinatura. Repetir somente esse caso evita uma miniatura
            // quebrada sem esconder erros reais de autenticacao ou permissao.
            for (let attempt = 0; attempt < retryDelays.length; attempt++) {
                if (retryDelays[attempt] > 0) {
                    await new Promise(resolve => setTimeout(resolve, retryDelays[attempt]));
                }

                res = await fetch(signEndpoint, {
                    method: 'POST',
                    headers,
                    body: JSON.stringify({ expiresIn: 600 })
                });

                if (res.ok || res.status !== 404 || attempt === retryDelays.length - 1) {
                    break;
                }
            }

            if (!res?.ok) {
                const txt = await res?.text().catch(() => '') || '';
                console.warn('[SIGN FAIL]', res?.status, txt, { input, path });
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
