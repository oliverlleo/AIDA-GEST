const test = require('node:test');
const assert = require('node:assert/strict');

global.window = global;
require('../js/modules/api-client.js');
require('../js/modules/storage-service.js');

const deps = {
    SUPABASE_URL: 'https://example.supabase.co',
    SUPABASE_KEY: 'public-key',
    state: {
        session: { access_token: 'user-token' },
        user: { workspace_id: 'workspace-id' }
    }
};

test('usa a imagem local enquanto a nova OS ainda nao existe', async (t) => {
    const originalFetch = global.fetch;
    const originalCreateObjectURL = global.URL.createObjectURL;
    const originalRevokeObjectURL = global.URL.revokeObjectURL;
    let fetchCalls = 0;
    let revokedUrl = null;

    t.after(() => {
        global.AIDAStorageService.clearLocalPhotoPreviews();
        global.fetch = originalFetch;
        global.URL.createObjectURL = originalCreateObjectURL;
        global.URL.revokeObjectURL = originalRevokeObjectURL;
    });

    global.URL.createObjectURL = () => 'blob:local-preview';
    global.URL.revokeObjectURL = (url) => { revokedUrl = url; };
    global.fetch = async (url) => {
        fetchCalls += 1;
        if (url.includes('/rpc/reserve_storage_upload')) return { ok: true, status: 200, json: async () => ({ reserved: true }) };
        return { ok: true, status: 200 };
    };

    const path = await global.AIDAStorageService.uploadTicketPhoto(
        { name: 'foto.png', type: 'image/png', size: 100 },
        'ticket-reservado',
        deps
    );
    const previewUrl = await global.AIDAStorageService.getPhotoUrl(path, deps);

    assert.equal(fetchCalls, 2);
    assert.equal(previewUrl, 'blob:local-preview');

    global.AIDAStorageService.forgetLocalPhotoPreview(path);
    assert.equal(revokedUrl, 'blob:local-preview');
});

test('repete a assinatura quando o objeto ainda responde 404', async (t) => {
    let calls = 0;
    const originalFetch = global.fetch;
    const originalSetTimeout = global.setTimeout;
    t.after(() => {
        global.fetch = originalFetch;
        global.setTimeout = originalSetTimeout;
    });

    global.setTimeout = (callback) => {
        callback();
        return 0;
    };
    global.fetch = async () => {
        calls += 1;
        if (calls < 3) {
            return {
                ok: false,
                status: 404,
                text: async () => 'Object not found'
            };
        }

        return {
            ok: true,
            status: 200,
            json: async () => ({ signedURL: '/object/sign/ticket_photos/photo?token=test' })
        };
    };

    const url = await global.AIDAStorageService.getPhotoUrl('workspace/ticket/photo.webp', deps);

    assert.equal(calls, 3);
    assert.equal(
        url,
        'https://example.supabase.co/storage/v1/object/sign/ticket_photos/photo?token=test'
    );
});

test('nao repete erros que nao sejam o 404 transitorio', async (t) => {
    let calls = 0;
    const originalFetch = global.fetch;
    const originalWarn = console.warn;
    t.after(() => {
        global.fetch = originalFetch;
        console.warn = originalWarn;
    });

    console.warn = () => {};
    global.fetch = async () => {
        calls += 1;
        return {
            ok: false,
            status: 403,
            text: async () => 'Forbidden'
        };
    };

    const url = await global.AIDAStorageService.getPhotoUrl('workspace/ticket/photo.webp', deps);

    assert.equal(calls, 1);
    assert.equal(url, '');
});

test('fotos e estoque reservam o mesmo path, tamanho e MIME com JWT antes do upload', async (t) => {
    const originalFetch = global.fetch;
    const originalCreateObjectURL = global.URL.createObjectURL;
    const originalRevokeObjectURL = global.URL.revokeObjectURL;
    t.after(() => {
        global.AIDAStorageService.clearLocalPhotoPreviews();
        global.fetch = originalFetch;
        global.URL.createObjectURL = originalCreateObjectURL;
        global.URL.revokeObjectURL = originalRevokeObjectURL;
    });
    global.URL.createObjectURL = () => 'blob:test';
    global.URL.revokeObjectURL = () => {};
    for (const [bucket, upload, file] of [
        ['ticket_photos', 'uploadTicketPhoto', { name: 'foto.HEIC', type: '', size: 20971520 }],
        ['inventory_images', 'uploadInventoryImage', { name: 'peça.webp', type: 'image/webp', size: 5242880 }]
    ]) {
        const calls = [];
        global.fetch = async (url, options) => {
            calls.push({ url, options });
            return { ok: true, status: 200, json: async () => ({ reserved: true }) };
        };
        const path = await global.AIDAStorageService[upload](file, 'operation-id', deps);
        assert.equal(calls.length, 2);
        assert.match(calls[0].url, /\/rest\/v1\/rpc\/reserve_storage_upload$/);
        const reservation = JSON.parse(calls[0].options.body);
        assert.deepEqual(reservation, {
            p_bucket_id: bucket, p_path: path, p_size: file.size,
            p_mime_type: bucket === 'ticket_photos' ? 'image/heic' : 'image/webp'
        });
        assert.equal(calls[0].options.headers.Authorization, 'Bearer user-token');
        assert.equal(calls[0].options.headers['x-workspace-id'], 'workspace-id');
        assert.ok(calls[1].url.endsWith(`/${bucket}/${path}`));
        assert.equal(calls[1].options.headers['Content-Type'], reservation.p_mime_type);
        assert.equal(calls[1].options.body, file);
    }
});

test('reserva recusada ou limitada nunca envia arquivo nem cria preview', async (t) => {
    const originalFetch = global.fetch;
    const originalError = console.error;
    t.after(() => { global.fetch = originalFetch; console.error = originalError; });
    console.error = () => {};
    for (const upload of ['uploadTicketPhoto', 'uploadInventoryImage']) {
        for (const status of [429, 403, 404]) {
            const calls = [];
            global.fetch = async (url) => {
                calls.push(url);
                return new Response(JSON.stringify({ code: 'test_error', message: 'Acesso indisponível.' }), {
                    status, headers: { 'Retry-After': '23' }
                });
            };
            await assert.rejects(global.AIDAStorageService[upload](
                { name: 'foto.png', type: 'image/png', size: 100 }, 'blocked', deps
            ), error => error.status === status && (status !== 429 || error.retryAfter === 23));
            assert.equal(calls.length, 1);
            assert.match(calls[0], /reserve_storage_upload$/);
            assert.equal([...global.AIDAStorageService.localPhotoPreviews.keys()].some(path => path.includes('/blocked/')), false);
        }
    }
});

test('rejeita arquivos inválidos e excessivos antes de reservar ou transferir', async (t) => {
    const originalFetch = global.fetch;
    const originalError = console.error;
    let calls = 0;
    global.fetch = async () => { calls++; throw new Error('Network must not be reached'); };
    console.error = () => {};
    t.after(() => { global.fetch = originalFetch; console.error = originalError; });
    const service = global.AIDAStorageService;
    const cases = [
        ['uploadTicketPhoto', { name: 'foto.jpg', type: 'image/jpeg', size: 20971521 }],
        ['uploadTicketPhoto', { name: 'arquivo.html', type: '', size: 1 }],
        ['uploadTicketPhoto', { name: 'fake.png', type: 'text/html', size: 1 }],
        ['uploadInventoryImage', { name: 'foto.gif', type: 'image/gif', size: 1 }],
        ['uploadInventoryImage', { name: 'foto.png', type: 'image/png', size: 5242881 }]
    ];
    for (const [upload, file] of cases) await assert.rejects(service[upload](file, 'id', deps));
    await assert.rejects(service.handleLogoUpload({ name: 'logo.png', type: 'image/png', size: 5242881 }, deps));
    await assert.rejects(service.handleLogoUpload({ name: 'logo.svg', type: 'image/svg+xml', size: 100 }, deps));
    assert.equal(calls, 0);
});

test('upload limitado não repete e conserva o erro do servidor', async (t) => {
    const originalFetch = global.fetch;
    const originalError = console.error;
    t.after(() => { global.fetch = originalFetch; console.error = originalError; });
    console.error = () => {};
    let calls = 0;
    global.fetch = async () => {
        calls++;
        return calls === 1
            ? new Response(JSON.stringify({ reserved: true }))
            : new Response('{}', { status: 429, headers: { 'Retry-After': '11' } });
    };
    await assert.rejects(global.AIDAStorageService.uploadTicketPhoto(
        { name: 'foto.png', type: 'image/png', size: 100 }, 'limited', deps
    ), error => error.status === 429 && error.retryAfter === 11);
    assert.equal(calls, 2);
});

test('logo usa a Edge sem reservar duas vezes e mantém GIF e MIME inferido', async (t) => {
    const originalFetch = global.fetch;
    t.after(() => { global.fetch = originalFetch; });
    const cases = [
        new File(['GIF89a'], 'logo.gif', { type: 'image/gif' }),
        new File(['png'], 'logo.png', { type: '' })
    ];
    for (const file of cases) {
        const calls = [];
        global.fetch = async (url, options) => {
            calls.push({ url, options });
            return new Response(JSON.stringify({ publicUrl: 'https://cdn.test/logo' }));
        };
        assert.equal(await global.AIDAStorageService.handleLogoUpload(file, deps), 'https://cdn.test/logo');
        assert.equal(calls.length, 1);
        assert.match(calls[0].url, /\/functions\/v1\/upload-workspace-logo$/);
        assert.equal(calls[0].options.headers['Content-Type'], undefined);
        assert.equal(calls[0].options.body.get('file').type, file.type || 'image/png');
    }
});
