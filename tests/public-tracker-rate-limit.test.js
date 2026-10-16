const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.join(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'acompanhar.html'), 'utf8');
const script = [...html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/gi)]
    .map(match => match[1]).find(source => source.includes('function tracker()'));
const ID = '11111111-1111-4111-8111-111111111111';
const TOKEN = '22222222-2222-4222-8222-222222222222';
const NOW = Date.UTC(2026, 9, 15, 20, 0, 0);

function runtime(response) {
    const values = new Map(), calls = [];
    let currentUrl = new URL(`https://techassist.pages.dev/acompanhar.html?id=${ID}&token=${TOKEN}`);
    const sandbox = {
        URL, URLSearchParams,
        Date: class extends Date { static now() { return NOW; } },
        console: { error() {}, warn() {} },
        document: { title: 'Acompanhamento' },
        SUPABASE_CONFIG: { URL: 'https://example.supabase.co', KEY: 'public-test-key' },
        sessionStorage: {
            getItem: key => values.get(key) || null,
            setItem: (key, value) => values.set(key, value),
            removeItem: key => values.delete(key)
        },
        location: {
            get href() { return currentUrl.href; },
            get search() { return currentUrl.search; }
        },
        history: { replaceState: (_state, _title, url) => { currentUrl = new URL(url); } },
        fetch: async (url, options) => { calls.push({ url, options }); return response; },
        setTimeout() { throw new Error('Public tracker must not retry automatically'); },
        setInterval() { throw new Error('Public tracker must not poll after a rate limit'); }
    };
    sandbox.window = sandbox;
    const context = vm.createContext(sandbox);
    vm.runInContext(fs.readFileSync(path.join(root, 'js/modules/api-client.js'), 'utf8'), context);
    vm.runInContext(script, context);
    return { state: vm.runInContext('tracker()', context), values, calls, url: () => currentUrl };
}

test('acompanhamento limitado mostra Retry-After e conserva o token para tentativa manual', async () => {
    for (const [retryAfter, seconds] of [
        ['27', 27],
        [new Date(NOW + 45000).toUTCString(), 45],
        [null, 60]
    ]) {
        const headers = retryAfter ? { 'Retry-After': retryAfter } : {};
        const { state, values, calls, url } = runtime(new Response('invalid JSON', { status: 429, headers }));
        await state.init();
        assert.equal(calls.length, 1);
        assert.equal(calls[0].options.method, 'POST');
        assert.deepEqual(JSON.parse(calls[0].options.body), { p_ticket_id: ID, p_public_token: TOKEN });
        assert.match(state.error, new RegExp(`Aguarde ${seconds} segundos`));
        assert.doesNotMatch(state.error, /Link inválido/);
        assert.equal(values.get(`tracker_token_${ID}`), TOKEN);
        assert.equal(url().searchParams.has('token'), false);
        assert.equal(state.ticket, null);
        assert.equal(state.loading, false);
    }
});

test('resposta válida sem OS continua invalidando o token e não exibe dados', async () => {
    const { state, values, calls } = runtime(new Response('[]', { status: 200 }));
    await state.init();
    assert.equal(calls.length, 1);
    assert.equal(values.has(`tracker_token_${ID}`), false);
    assert.match(state.error, /Link inválido ou desatualizado/);
    assert.equal(state.ticket, null);
    assert.equal(state.loading, false);
});

test('link válido mantém acompanhamento e falha de acesso não expõe detalhes internos', async () => {
    const ticket = { os_number: 'OS-TEST', status: 'Analise Tecnica', device_model: 'Aparelho sintético' };
    const success = runtime(new Response(JSON.stringify([ticket])));
    await success.state.init();
    assert.equal(success.state.error, null);
    assert.equal(success.state.ticket.os_number, 'OS-TEST');
    assert.equal(success.values.get(`tracker_token_${ID}`), TOKEN);

    const denied = runtime(new Response(JSON.stringify({ message: 'private database details' }), { status: 403 }));
    await denied.state.init();
    assert.match(denied.state.error, /Não foi possível carregar/);
    assert.doesNotMatch(denied.state.error, /private database/);
    assert.equal(denied.state.ticket, null);
    assert.equal(denied.values.has(`tracker_token_${ID}`), false);
});
