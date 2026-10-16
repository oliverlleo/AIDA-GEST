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

test('gravação envia a revisão da OS separada dos campos editáveis', async (t) => {
    const originalFetch = global.fetch;
    let request;
    t.after(() => { global.fetch = originalFetch; });
    global.fetch = async (_url, options) => {
        request = options;
        return new Response(JSON.stringify([{ id: 'ticket-id', revision: 8 }]));
    };
    const result = await global.AIDAApiClient.supabaseFetch(
        'tickets?id=eq.ticket-id', 'PATCH', { tech_notes: 'rascunho' }, deps,
        { ticketVersion: { id: 'ticket-id', revision: 7 } }
    );
    assert.deepEqual(JSON.parse(request.headers['x-aida-ticket-version']), { id: 'ticket-id', revision: 7 });
    assert.deepEqual(JSON.parse(request.body), { tech_notes: 'rascunho' });
    assert.equal(result[0].revision, 8);
});

test('revisão ausente ou inválida no contexto informado falha antes da requisição', async (t) => {
    const originalFetch = global.fetch;
    let calls = 0;
    t.after(() => { global.fetch = originalFetch; });
    global.fetch = async () => { calls++; throw new Error('unexpected request'); };
    for (const revision of [undefined, null, 0, -1, '01', '1.0', '9007199254740992', NaN, Infinity, 1.5]) {
        await assert.rejects(global.AIDAApiClient.supabaseFetch(
            'tickets?id=eq.ticket-id', 'PATCH', {}, deps,
            { ticketVersion: { id: 'ticket-id', revision } }
        ), /Reabra a OS/);
    }
    assert.equal(calls, 0);
});

test('revisão serializada em texto pelo módulo de mutações é aceita e normalizada', async (t) => {
    const originalFetch = global.fetch;
    let header;
    t.after(() => { global.fetch = originalFetch; });
    global.fetch = async (_url, options) => {
        header = options.headers['x-aida-ticket-version'];
        return new Response('[]');
    };
    await global.AIDAApiClient.supabaseFetch('tickets', 'PATCH', {}, deps,
        { ticketVersion: { id: 'ticket-id', revision: '7' } });
    assert.deepEqual(JSON.parse(header), { id: 'ticket-id', revision: 7 });
});

test('conflito preserva HTTP409 e nunca repete a gravação automaticamente', async (t) => {
    const originalFetch = global.fetch;
    let calls = 0;
    t.after(() => { global.fetch = originalFetch; });
    global.fetch = async () => {
        calls++;
        return new Response(JSON.stringify({ code: 'PT409', message: 'Esta OS foi alterada em outro computador. Revise antes de salvar.' }), { status: 409 });
    };
    await assert.rejects(global.AIDAApiClient.supabaseFetch(
        'tickets?id=eq.ticket-id', 'PATCH', {}, deps,
        { ticketVersion: { id: 'ticket-id', revision: 1 } }
    ), error => error.status === 409 && error.code === 'PT409' && /outro computador/.test(error.message));
    assert.equal(calls, 1);
});

test('resposta da empresa ou identidade anterior é descartada inclusive durante leitura do JSON', async (t) => {
    const originalFetch = global.fetch;
    t.after(() => { global.fetch = originalFetch; });
    for (const change of ['workspace', 'identity', 'logout']) {
        const localDeps = { ...deps, state: { user: { workspace_id: 'A' }, session: { user: { id: 'user-A' }, access_token: 'token-A' } } };
        global.fetch = async () => ({ ok: true, status: 200, json: async () => {
            if (change === 'workspace') localDeps.state.user.workspace_id = 'B';
            if (change === 'identity') localDeps.state.session.user.id = 'user-B';
            if (change === 'logout') localDeps.state.session = null;
            return [{ private: 'previous workspace' }];
        } });
        await assert.rejects(global.AIDAApiClient.supabaseFetch('tickets', 'GET', null, localDeps),
            error => error.name === 'AbortError' && error.contextChanged === true);
    }
});

test('renovação do JWT da mesma identidade não descarta uma resposta válida', async (t) => {
    const originalFetch = global.fetch;
    t.after(() => { global.fetch = originalFetch; });
    const localDeps = { ...deps, state: { user: { workspace_id: 'A' }, session: { user: { id: 'user-A' }, access_token: 'token-A' } } };
    global.fetch = async () => {
        localDeps.state.session.access_token = 'refreshed-token';
        return new Response(JSON.stringify([{ id: 'ticket' }]));
    };
    assert.deepEqual(await global.AIDAApiClient.supabaseFetch('tickets', 'GET', null, localDeps), [{ id: 'ticket' }]);
});

test('recebimentos e remarcações enviam a versão da própria operação e recusam contexto inválido', async (t) => {
    const originalFetch = global.fetch;
    let calls = 0, header;
    t.after(() => { global.fetch = originalFetch; });
    global.fetch = async (_url, options) => { calls++; header = options.headers['x-aida-operation-version']; return new Response('{}'); };
    for (const resource of ['inventory_purchases', 'ticket_appointments']) {
        await global.AIDAApiClient.supabaseFetch('rpc/operation', 'POST', {}, deps,
            { operationVersion: { resource, id: 'operation-id', revision: '2' } });
        assert.deepEqual(JSON.parse(header), { resource, id: 'operation-id', revision: 2 });
    }
    for (const operationVersion of [{ resource: 'profiles', id: 'id', revision: 2 }, { resource: 'inventory_purchases', id: 'id', revision: null }]) {
        await assert.rejects(global.AIDAApiClient.supabaseFetch('rpc/operation', 'POST', {}, deps, { operationVersion }), /Reabra esta operação/);
    }
    assert.equal(calls, 2);
});

test('requisição pendurada tem prazo e gravação incerta não é repetida', async (t) => {
    const originalFetch = global.fetch, originalTimeout = global.setTimeout, originalClear = global.clearTimeout;
    let abortRequest, calls = 0, cancelled = 0;
    t.after(() => { global.fetch = originalFetch; global.setTimeout = originalTimeout; global.clearTimeout = originalClear; });
    global.setTimeout = (callback, duration) => { assert.equal(duration, 30000); abortRequest = callback; return 1; };
    global.clearTimeout = () => { cancelled++; };
    global.fetch = async (_url, options) => {
        calls++;
        return await new Promise((_resolve, reject) => {
            options.signal.addEventListener('abort', () => reject(Object.assign(new Error('aborted'), { name: 'AbortError' })));
            queueMicrotask(abortRequest);
        });
    };
    await assert.rejects(global.AIDAApiClient.supabaseFetch('tickets', 'PATCH', {}, deps),
        error => error.code === 'AIDA_TIMEOUT' && error.unknownCommit === true && /Consulte o estado atual/.test(error.message));
    assert.equal(calls, 1);
    assert.equal(cancelled, 1);
});

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
