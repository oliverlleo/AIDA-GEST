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

test('limite temporário preserva status, código e Retry-After sem repetir gravações', async (t) => {
    const originalFetch = global.fetch;
    t.after(() => { global.fetch = originalFetch; });
    for (const method of ['POST', 'PATCH', 'DELETE']) {
        let calls = 0;
        global.fetch = async () => {
            calls++;
            return new Response(JSON.stringify({ message: 'Internal limit details', code: 'PT429' }), {
                status: 429, headers: { 'Retry-After': '17' }
            });
        };
        await assert.rejects(
            global.AIDAApiClient.supabaseFetch('tickets', method, { id: 'ticket' }, deps),
            error => error.status === 429 && error.code === 'PT429' && error.retryAfter === 17
                && /17 segundos/.test(error.message) && !/Internal/.test(error.message)
        );
        assert.equal(calls, 1);
    }
});

test('Retry-After aceita data HTTP e usa intervalo seguro quando ausente ou inválido', () => {
    const client = global.AIDAApiClient;
    const now = Date.UTC(2026, 9, 15, 20, 0, 0);
    const response = value => ({ headers: { get: () => value } });
    assert.equal(client.getRetryAfter(response(new Date(now + 45000).toUTCString()), 60, now), 45);
    assert.equal(client.getRetryAfter(response('0'), 60, now), 1);
    assert.equal(client.getRetryAfter(response('invalid'), 60, now), 60);
    assert.equal(client.getRetryAfter(response(null), 60, now), 60);
});

test('respostas vazias e erros de tamanho/formato mantêm mensagens legíveis', async (t) => {
    const originalFetch = global.fetch;
    t.after(() => { global.fetch = originalFetch; });
    for (const [status, expected] of [[429, /Aguarde 60 segundos/], [413, /tamanho permitido/], [415, /formato de arquivo/]]) {
        let calls = 0;
        global.fetch = async () => { calls++; return new Response('invalid JSON', { status }); };
        await assert.rejects(global.AIDAApiClient.supabaseFetch('rpc/test', 'POST', {}, deps),
            error => error.status === status && expected.test(error.message));
        assert.equal(calls, 1);
    }
    const error = global.AIDAApiClient.createApiError({ status: 403 }, { message: 'Acesso negado.', code: '42501' });
    assert.equal(error.message, 'Acesso negado.');
    assert.equal(error.code, '42501');
    assert.equal(error.retryAfter, undefined);
});
