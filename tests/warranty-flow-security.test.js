const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const migration = fs.readFileSync(path.join(root, 'add_warranty_flow.sql'), 'utf8');
const legacyMigration = fs.readFileSync(path.join(root, 'support_legacy_warranty_customer_link.sql'), 'utf8');
const rollback = fs.readFileSync(path.join(root, 'rollback_warranty_flow.sql'), 'utf8');

test('warranty links preserve the original, the claim and the paid follow-up OS', () => {
    assert.match(migration, /warranty_origin_ticket_id uuid/i);
    assert.match(migration, /warranty_source_claim_id uuid/i);
    assert.match(migration, /warranty_converted_ticket_id uuid/i);
    assert.match(migration, /foreign key \(warranty_origin_ticket_id\)[\s\S]*references public\.tickets\(id\)/i);
    assert.match(migration, /create unique index if not exists idx_tickets_warranty_source_claim_unique/i);
    assert.match(migration, /Os vinculos da garantia nao podem ser alterados depois da abertura/i);
});

test('direct ticket writes receive the same tenant, eligibility and actor protection', () => {
    assert.match(migration, /trigger aida_enforce_ticket_warranty[\s\S]*before insert or update/i);
    assert.match(migration, /get_current_actor_context\(\)/i);
    assert.match(migration, /new\.workspace_id is distinct from v_ctx\.workspace_id/i);
    assert.match(migration, /v_ctx\.is_admin[\s\S]*v_ctx\.is_attendant/i);
    assert.match(migration, /v_origin\.repair_successful is distinct from true/i);
    assert.match(migration, /v_origin\.status <> 'Finalizado'/i);
    assert.match(migration, /v_expiry < now\(\)/i);
    assert.match(migration, /Ja existe um retorno em garantia aberto para esta OS/i);
});

test('technical warranty decision is structured and restricted to assigned technician or admin', () => {
    assert.match(migration, /function public\.complete_warranty_analysis\(/i);
    assert.match(migration, /v_ticket\.technician_id = v_ctx\.actor_employee_id/i);
    assert.match(migration, /length\(btrim\(coalesce\(p_report, ''\)\)\) < 20/i);
    assert.match(migration, /when not p_covered then 'Aprovacao'/i);
    assert.match(migration, /when coalesce\(p_needs_parts, false\) then 'Compra Peca'/i);
    assert.match(migration, /else 'Andamento Reparo'/i);
});

test('legacy OS can be adopted only by matching customer name and an authorized actor', () => {
    assert.match(legacyMigration, /function private\.adopt_legacy_warranty_customer\(\)/i);
    assert.match(legacyMigration, /v_ctx\.is_admin[\s\S]*v_ctx\.is_attendant/i);
    assert.match(legacyMigration, /new\.workspace_id is distinct from v_ctx\.workspace_id/i);
    assert.match(legacyMigration, /lower\(btrim\(v_customer\.name\)\) <> lower\(btrim\(v_origin\.client_name\)\)/i);
    assert.match(legacyMigration, /set customer_id = v_customer\.id/i);
    assert.match(legacyMigration, /revoke all on function private\.adopt_legacy_warranty_customer\(\) from public/i);
});

test('public warranty reads are bounded, retain RLS and never accept workspace from the client', () => {
    assert.match(migration, /function public\.get_warranty_eligible_tickets\(/i);
    assert.match(migration, /function public\.get_warranty_ticket_summaries\(/i);
    const invokers = migration.match(/security invoker/gi) || [];
    assert.ok(invokers.length >= 4);
    assert.match(migration, /p_limit < 1 or p_limit > 50/i);
    assert.match(migration, /cardinality\(p_ticket_ids\) > 50/i);
    assert.match(migration, /get_warranty_eligible_tickets\(\s*p_customer_id uuid,\s*p_search text[\s\S]*p_limit integer/i);
    assert.match(migration, /get_warranty_ticket_summaries\(p_ticket_ids uuid\[\]\)/i);
    assert.match(migration, /revoke all on function public\.get_warranty_eligible_tickets[\s\S]*from public/i);
    assert.match(migration, /grant execute on function public\.get_warranty_eligible_tickets[\s\S]*to anon, authenticated/i);
    assert.doesNotMatch(migration, /'warranty_technical_report', t\.warranty_technical_report/i);
});

test('rollback removes only warranty objects and columns', () => {
    assert.match(rollback, /drop trigger if exists aida_enforce_ticket_warranty/i);
    assert.match(rollback, /drop function if exists public\.complete_warranty_analysis/i);
    assert.match(rollback, /drop column if exists warranty_claim/i);
    assert.doesNotMatch(rollback, /drop table if exists public\.tickets/i);
    assert.doesNotMatch(rollback, /delete from public\.tickets/i);
});
