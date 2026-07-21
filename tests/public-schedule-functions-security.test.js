const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const migration = fs.readFileSync(
    path.join(__dirname, '..', 'harden_public_schedule_functions.sql'),
    'utf8'
);
const rollback = fs.readFileSync(
    path.join(__dirname, '..', 'rollback_public_schedule_functions.sql'),
    'utf8'
);

const protectedFunctions = [
    'get_schedule_availability',
    'get_unscheduled_tickets',
    'get_schedule_dashboard',
    'get_ticket_appointments',
    'create_ticket_with_optional_analysis_schedule',
    'create_ticket_appointment',
    'create_schedule_block',
    'delete_schedule_block'
];

test('RPCs publicas da agenda validam o ator antes de chamar a implementacao privada', () => {
    for (const functionName of protectedFunctions) {
        assert.match(migration, new RegExp(`create function public\\.${functionName}\\(`));
        assert.match(migration, new RegExp(`return private\\.${functionName}\\(`));
    }

    const actorChecks = migration.match(
        /select \* into v_ctx from public\.get_current_actor_context\(\);/g
    ) || [];
    assert.equal(actorChecks.length, protectedFunctions.length);
});

test('implementacoes privadas e helpers internos nao ficam executaveis pelo cliente', () => {
    for (const functionName of protectedFunctions) {
        assert.match(
            migration,
            new RegExp(`revoke all on function private\\.${functionName}\\(`)
        );
    }

    for (const helper of [
        'get_ticket_appointments_state',
        'get_expanded_blocks',
        'validate_appointment_capacity',
        'enforce_configurable_appointment',
        'sync_ticket_schedule_state',
        'set_schedule_updated_at'
    ]) {
        assert.match(
            migration,
            new RegExp(`revoke all on function public\\.${helper}\\(`)
        );
    }
});

test('mudanca da agenda possui rollback para as oito implementacoes originais', () => {
    for (const functionName of protectedFunctions) {
        assert.match(
            rollback,
            new RegExp(`alter function private\\.${functionName}\\(`)
        );
    }
});
