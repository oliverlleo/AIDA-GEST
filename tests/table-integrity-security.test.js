const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const migration = fs.readFileSync(
    path.join(__dirname, '..', 'harden_table_integrity.sql'),
    'utf8'
);
const rollback = fs.readFileSync(
    path.join(__dirname, '..', 'rollback_table_integrity.sql'),
    'utf8'
);
const fkIndexes = fs.readFileSync(
    path.join(__dirname, '..', 'complete_table_integrity_fk_indexes.sql'),
    'utf8'
);

test('orphan is backed up before removal and can be restored', () => {
    assert.match(migration, /quarantined_rows/);
    assert.match(migration, /delete from public\.defect_options/);
    assert.match(rollback, /jsonb_to_recordset/);
    assert.match(rollback, /insert into public\.defect_options/);
});

test('workspace and tenant relationships are enforced in the database', () => {
    assert.match(migration, /tickets_workspace_id_fkey/);
    assert.match(migration, /tickets_workspace_technician_fkey/);
    assert.match(migration, /ticket_appointments_workspace_ticket_fkey/);
    assert.match(migration, /internal_notes_workspace_ticket_fkey/);
    assert.match(migration, /references public\.employees\(workspace_id, id\)/);
    assert.match(migration, /references public\.tickets\(workspace_id, id\)/);
});

test('new OS numbers are protected without rewriting legacy duplicates', () => {
    assert.match(migration, /private\.enforce_ticket_os_integrity/);
    assert.match(migration, /pg_advisory_xact_lock/);
    assert.match(migration, /before insert or update of workspace_id, os_number, deleted_at/);
    assert.match(migration, /Já existe uma OS ativa com esse número nesta empresa/);
    assert.doesNotMatch(migration, /update public\.tickets[\s\S]*set os_number/i);
});

test('JSON defaults and shapes match the application data model', () => {
    assert.match(migration, /alter column checklist_data set default '\[\]'::jsonb/);
    assert.match(migration, /tickets_json_shapes_check/);
    assert.match(migration, /checklist_templates_shape_check/);
    assert.match(migration, /jsonb_typeof\(tracker_config\) = 'object'/);
});

test('foreign-key indexes and a complete rollback are included', () => {
    assert.match(migration, /ticket_logs_ticket_id_idx/);
    assert.match(migration, /notifications_ticket_id_idx/);
    assert.match(migration, /workspaces_owner_id_idx/);
    assert.match(fkIndexes, /internal_notes_workspace_ticket_idx/);
    assert.match(fkIndexes, /tickets_workspace_outsourced_company_idx/);
    assert.match(rollback, /drop trigger if exists zz_aida_enforce_ticket_os_integrity/);
    assert.match(rollback, /drop constraint if exists tickets_workspace_technician_fkey/);
    assert.match(rollback, /alter column checklist_data set default '\{\}'::jsonb/);
    assert.match(rollback, /drop index if exists public\.internal_notes_workspace_ticket_idx/);
    assert.match(rollback, /drop index if exists public\.tickets_workspace_outsourced_company_idx/);
});
