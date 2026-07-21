const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const migration = fs.readFileSync(
    path.join(__dirname, '..', 'harden_schedule_concurrency.sql'),
    'utf8'
);
const rollback = fs.readFileSync(
    path.join(__dirname, '..', 'rollback_schedule_concurrency.sql'),
    'utf8'
);
const main = fs.readFileSync(path.join(__dirname, '..', 'js', 'main.js'), 'utf8');
const index = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');

test('capacidade e serializada por tecnico dentro da transacao', () => {
    assert.match(migration, /pg_advisory_xact_lock/);
    assert.match(migration, /aida_schedule/);
    assert.match(migration, /aida_ticket_appointment/);
});

test('duplicidade ativa por OS e etapa possui garantia unica no banco', () => {
    assert.match(
        migration,
        /create unique index if not exists ticket_appointments_active_ticket_type_uidx/
    );
    assert.match(migration, /where deleted_at is null and status <> 'cancelled'/);
});

test('escritas diretas e mutacoes da mesma agenda tambem ficam protegidas', () => {
    assert.match(migration, /trg_ticket_appointments_concurrent_capacity/);
    assert.match(migration, /for update/g);
    assert.match(migration, /private\.reschedule_ticket_appointment/);
    assert.match(migration, /private\.cancel_ticket_appointment/);
    assert.match(migration, /private\.start_ticket_appointment/);
    assert.match(migration, /private\.complete_ticket_appointment/);
});

test('etapa possui rollback do indice, trigger e wrappers', () => {
    assert.match(rollback, /drop index if exists public\.ticket_appointments_active_ticket_type_uidx/);
    assert.match(rollback, /drop trigger if exists trg_ticket_appointments_concurrent_capacity/);
    assert.match(rollback, /pre_schedule_concurrency_20260721/);
});

test('front bloqueia repeticao e traduz conflito sem expor erro SQL', () => {
    assert.match(main, /async selectScheduleSlot\(dateStr, slot\) \{\s*if \(this\.loading\) return;/);
    assert.match(main, /async submitReschedule\(\) \{\s*if \(this\.loading\) return;/);
    assert.match(main, /AIDAScheduleErrorService\.getUserMessage/);
    assert.match(index, /schedule-error-service\.js\?v=1/);
    assert.match(index, /:disabled="loading"/);
});
