const test = require('node:test');
const assert = require('node:assert/strict');

global.window = global;
require('../js/modules/auth-session-service.js');

test('cadastro de administrador bloqueia senha apenas numerica antes do Supabase', async () => {
    let signUpCalled = false;
    let notification = '';
    let loadingCalled = false;

    await global.AIDAAuthSessionService.registerAdmin({
        state: { registerForm: { email: 'admin@example.com', password: '12345678' } },
        supabaseClient: {
            auth: {
                signUp: async () => {
                    signUpCalled = true;
                    return { data: {}, error: null };
                }
            }
        },
        notify: message => { notification = message; },
        setLoading: () => { loadingCalled = true; }
    });

    assert.equal(signUpCalled, false);
    assert.equal(loadingCalled, false);
    assert.equal(notification, 'A senha deve incluir pelo menos uma letra e um número.');
});

test('cadastro de administrador envia senha valida ao Supabase', async () => {
    let submittedPassword = '';
    let notification = '';

    await global.AIDAAuthSessionService.registerAdmin({
        state: { registerForm: { email: 'admin@example.com', password: 'Admin123' } },
        supabaseClient: {
            auth: {
                signUp: async ({ password }) => {
                    submittedPassword = password;
                    return { data: { user: { id: 'user-id' }, session: null }, error: null };
                }
            }
        },
        notify: message => { notification = message; },
        setLoading: () => {}
    });

    assert.equal(submittedPassword, 'Admin123');
    assert.equal(notification, 'Verifique seu e-mail.');
});

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
