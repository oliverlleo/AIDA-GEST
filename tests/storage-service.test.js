const test = require('node:test');
const assert = require('node:assert/strict');

global.window = global;
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
    global.fetch = async () => {
        fetchCalls += 1;
        return { ok: true, status: 200 };
    };

    const path = await global.AIDAStorageService.uploadTicketPhoto(
        { name: 'foto.png', type: 'image/png' },
        'ticket-reservado',
        deps
    );
    const previewUrl = await global.AIDAStorageService.getPhotoUrl(path, deps);

    assert.equal(fetchCalls, 1);
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
