const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

global.window = global;
require('../js/modules/logs-notifications-service.js');

test('historico grava pela RLS sem solicitar a linha protegida de volta', async () => {
    let request;

    await global.AIDALogsNotificationsService.logTicketAction(
        'ticket-id',
        'Finalizou Analise',
        'Detalhes do teste',
        {
            state: { user: { name: 'Nome enviado pelo navegador' }, view: 'bench' },
            supabaseFetch: async (endpoint, method, body, requestOptions) => {
                request = { endpoint, method, body, requestOptions };
                return null;
            },
            fetchGlobalLogs: () => {}
        }
    );

    assert.equal(request.endpoint, 'ticket_logs');
    assert.equal(request.method, 'POST');
    assert.deepEqual(request.body, {
        ticket_id: 'ticket-id',
        action: 'Finalizou Analise',
        details: 'Detalhes do teste'
    });
    assert.equal(Object.hasOwn(request.body, 'user_name'), false);
    assert.deepEqual(request.requestOptions, { returnRepresentation: false });
});

test('main encaminha a opcao returnRepresentation ao cliente da API', () => {
    const source = fs.readFileSync(path.join(__dirname, '..', 'js', 'main.js'), 'utf8');

    assert.match(
        source,
        /supabaseFetch:\s*\(ep,\s*method,\s*payload,\s*requestOptions\)\s*=>\s*this\.supabaseFetch\(ep,\s*method,\s*payload,\s*requestOptions\)/
    );
});
