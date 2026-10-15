const test = require('node:test');
const assert = require('node:assert/strict');

global.window = global;
require('../js/modules/api-client.js');

const deps = {
    SUPABASE_URL: 'https://example.supabase.co',
    SUPABASE_KEY: 'public-key',
    state: {
        session: { access_token: 'auth-user-token' },
        user: { workspace_id: 'workspace-id' },
        employeeSession: { token: 'employee-token' }
    }
};

test('grava historico sem exigir leitura da linha devolvida', async (t) => {
    const originalFetch = global.fetch;
    let capturedOptions;
    t.after(() => { global.fetch = originalFetch; });

    global.fetch = async (_url, options) => {
        capturedOptions = options;
        return { ok: true, status: 201 };
    };

    const result = await global.AIDAApiClient.supabaseFetch(
        'ticket_logs',
        'POST',
        { ticket_id: 'ticket-id', action: 'Finalizou Analise' },
        deps,
        { returnRepresentation: false }
    );

    assert.equal(result, null);
    assert.equal(capturedOptions.headers.Prefer, 'return=minimal');
    assert.equal(capturedOptions.headers.Authorization, 'Bearer auth-user-token');
    assert.equal(capturedOptions.headers['x-workspace-id'], 'workspace-id');
    assert.equal(capturedOptions.headers['x-employee-token'], undefined);
});

test('upsert de agenda preserva JWT e empresa e usa merge sem exigir representacao', async (t) => {
    const originalFetch = global.fetch;
    let request;
    t.after(() => { global.fetch = originalFetch; });
    global.fetch = async (url, options) => {
        request = { url, options };
        return { ok: true, status: 204 };
    };
    const payload = { technician_id: 'technician-id', workspace_id: 'workspace-id', settings: { slotDuration: 30 } };
    const result = await global.AIDAApiClient.supabaseFetch(
        'technician_schedule_settings?on_conflict=technician_id', 'POST', payload, deps,
        { upsert: true, returnRepresentation: false }
    );
    assert.equal(result, null);
    assert.equal(request.url, 'https://example.supabase.co/rest/v1/technician_schedule_settings?on_conflict=technician_id');
    assert.equal(request.options.headers.Prefer, 'resolution=merge-duplicates,return=minimal');
    assert.equal(request.options.headers.Authorization, 'Bearer auth-user-token');
    assert.equal(request.options.headers['x-workspace-id'], 'workspace-id');
    assert.deepEqual(JSON.parse(request.options.body), payload);
});
