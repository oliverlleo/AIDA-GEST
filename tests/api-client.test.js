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
