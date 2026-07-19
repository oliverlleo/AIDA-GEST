const test = require('node:test');
const assert = require('node:assert/strict');

global.window = global;
require('../js/modules/employee-service.js');

test('atendente carrega o diretorio seguro sem chamar RPC administrativa', async () => {
    const state = {
        user: { workspace_id: 'workspace-id', roles: ['atendente'] },
        employeeSession: { token: 'employee-token' },
        employees: []
    };
    let capturedEndpoint;

    await global.AIDAEmployeeService.fetchEmployees({
        state,
        supabaseFetch: async (endpoint) => {
            capturedEndpoint = endpoint;
            return [{ id: 'tech-id', name: 'Tecnico', roles: ['tecnico'] }];
        }
    });

    assert.match(capturedEndpoint, /^employees\?select=/);
    assert.match(capturedEndpoint, /workspace_id=eq\.workspace-id/);
    assert.doesNotMatch(capturedEndpoint, /password_hash/);
    assert.equal(state.employees[0].name, 'Tecnico');
    assert.equal(state.employees[0].active_sessions, 0);
});

test('administrador recebe somente o resumo seguro das contas', async () => {
    const state = {
        session: { access_token: 'admin-token' },
        user: { workspace_id: 'workspace-id', roles: ['admin'] },
        employees: []
    };
    const calls = [];

    await global.AIDAEmployeeService.fetchEmployees({
        state,
        supabaseFetch: async (endpoint, method, payload) => {
            calls.push({ endpoint, method, payload });
            if (endpoint.startsWith('employees?')) {
                return [{ id: 'employee-id', name: 'Ana', roles: ['tecnico'] }];
            }
            return [{
                employee_id: 'employee-id',
                manual_blocked: true,
                active_sessions: 2,
                failed_attempts: 4
            }];
        }
    });

    assert.equal(calls[1].endpoint, 'rpc/get_employee_security_status');
    assert.deepEqual(calls[1].payload, { p_workspace_id: 'workspace-id' });
    assert.equal(state.employees[0].manual_blocked, true);
    assert.equal(state.employees[0].active_sessions, 2);
    assert.equal(state.employees[0].password_hash, undefined);
});

test('politica de senha exige tamanho, letra e numero', () => {
    const service = global.AIDAEmployeeService;
    assert.match(service.getPasswordPolicyError('abc123'), /8 caracteres/);
    assert.match(service.getPasswordPolicyError('abcdefgh'), /letra e um número/);
    assert.match(service.getPasswordPolicyError('12345678'), /letra e um número/);
    assert.equal(service.getPasswordPolicyError('Senha123'), '');
    assert.match(service.getPasswordPolicyError('á'.repeat(40) + '1A'), /72 bytes/);
});

test('senha temporaria aceita formato simples e exige somente seis caracteres', () => {
    const service = global.AIDAEmployeeService;
    assert.match(service.getTemporaryPasswordPolicyError('12345'), /6 caracteres/);
    assert.equal(service.getTemporaryPasswordPolicyError('123456'), '');
    assert.equal(service.getTemporaryPasswordPolicyError('abcdef'), '');
});

test('criacao invalida e barrada antes da chamada ao banco', async () => {
    let called = false;
    let notification = '';
    await global.AIDAEmployeeService.createEmployee({
        state: {
            user: { workspace_id: 'workspace-id' },
            employeeForm: { name: 'Ana', username: 'ana', password: 'fraca', roles: ['tecnico'] }
        },
        supabaseFetch: async () => { called = true; },
        notify: message => { notification = message; },
        setLoading: () => {},
        fetchEmployees: async () => {},
        closeModal: () => {}
    });

    assert.equal(called, false);
    assert.match(notification, /6 caracteres/);
});
