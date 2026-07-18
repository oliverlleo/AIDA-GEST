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
});
