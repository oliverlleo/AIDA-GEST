const test = require('node:test');
const assert = require('node:assert/strict');

global.window = global;
require('../js/modules/auth-session-service.js');

test('login recusado usa mensagem generica sem revelar bloqueio ou usuario', async () => {
    let notification = '';
    const state = {
        loginForm: { company_code: 'empresa', username: 'ana', password: 'incorreta' }
    };

    await global.AIDAAuthSessionService.loginEmployee({
        state,
        supabaseFetch: async () => [],
        notify: message => { notification = message; },
        setLoading: () => {}
    });

    assert.equal(notification, 'Credenciais inválidas ou acesso temporariamente indisponível.');
});

test('revalidacao periodica distingue indisponibilidade de sessao invalida', async () => {
    const state = { employeeSession: { token: 'token-id' } };
    const expected = new Error('rede indisponivel');

    await assert.rejects(
        global.AIDAAuthSessionService.validateSessionToken({
            state,
            supabaseFetch: async () => { throw expected; },
            throwOnError: true
        }),
        expected
    );
});

test('sessao revogada retorna nulo sem expor dados', async () => {
    const result = await global.AIDAAuthSessionService.validateSessionToken({
        state: { employeeSession: { token: 'token-id' } },
        supabaseFetch: async () => [{ valid: false }]
    });
    assert.equal(result, null);
});
