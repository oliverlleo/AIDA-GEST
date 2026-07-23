const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const migration = fs.readFileSync(path.join(root, 'add_customer_registry.sql'), 'utf8');
const rollback = fs.readFileSync(path.join(root, 'rollback_customer_registry.sql'), 'utf8');

test('customer schema is tenant-bound, soft-deleted, and only name is required', () => {
    assert.match(migration, /create table if not exists public\.customers/i);
    assert.match(migration, /workspace_id uuid not null/i);
    assert.match(migration, /name text not null/i);
    assert.match(migration, /deleted_at timestamptz/i);
    assert.match(migration, /unique \(workspace_id, id\)/i);
    assert.match(migration, /tickets_workspace_customer_fkey[\s\S]*foreign key \(workspace_id, customer_id\)[\s\S]*references public\.customers\(workspace_id, id\)/i);
    assert.doesNotMatch(migration, /\b(update|insert into)\s+public\.tickets[\s\S]*where\s+customer_id\s+is\s+null/i);
});

test('customer RLS is limited to the current workspace admin and attendant', () => {
    assert.match(migration, /alter table public\.customers enable row level security/i);
    assert.match(migration, /alter table public\.customers force row level security/i);
    assert.match(migration, /get_current_actor_context\(\)/i);
    assert.match(migration, /ctx\.is_admin or ctx\.is_attendant/i);
    assert.match(migration, /workspace_id = \([\s\S]*ctx\.workspace_id/i);
    assert.doesNotMatch(migration, /auth\.role\(\)/i);
    assert.match(migration, /current_user not in \('anon', 'authenticated'\)/i);
    assert.doesNotMatch(migration, /to\s+service_role/i);
});

test('module defaults on and blocks all customer RPCs when disabled', () => {
    assert.match(migration, /'customers', true/i);
    assert.match(migration, /aida_config_bool\(v_config, 'modules', 'customers', true\)/i);
    const moduleGuards = migration.match(/if not public\.aida_customers_enabled\(\) then/gi) || [];
    assert.ok(moduleGuards.length >= 4, 'read, ticket, save and linking paths must enforce the module');
    assert.match(migration, /coalesce\(v_config -> 'modules', '\{\}'::jsonb\) \|\| jsonb_build_object/i);
    assert.match(migration, /function public\.aida_customers_enabled\(\)[\s\S]*get_current_actor_context\(\)/i);
    assert.match(migration, /revoke all on function public\.aida_customers_enabled\(\) from public/i);
});

test('public customer APIs derive workspace from actor and retain RLS', () => {
    for (const signature of [
        /function public\.get_customer_page\(/i,
        /function public\.get_customer_ticket_page\(/i,
        /function public\.save_customer\(/i
    ]) {
        assert.match(migration, signature);
    }
    const invokers = migration.match(/security invoker/gi) || [];
    assert.ok(invokers.length >= 5, 'RPCs and identity triggers must be invoker functions');
    assert.doesNotMatch(migration, /p_workspace_id/i);
    assert.match(migration, /revoke all on function public\.get_customer_page[\s\S]*from public/i);
    assert.match(migration, /grant execute on function public\.get_customer_page[\s\S]*to anon, authenticated/i);
    assert.match(migration, /get_customer_page\(text, integer, jsonb, boolean\)/i);
    assert.match(migration, /get_customer_ticket_page\(uuid, text, integer, jsonb, boolean\)/i);
    assert.match(migration, /grant select, insert, update on table public\.customers to anon, authenticated/i);
    assert.doesNotMatch(migration, /grant\s+delete\s+on\s+table\s+public\.customers/i);
});

test('customer and ticket pages are bounded keyset queries with light cards', () => {
    const boundedLimits = migration.match(/p_limit < 1 or p_limit > 50/gi) || [];
    assert.equal(boundedLimits.length, 2);
    const optionalTotals = migration.match(/p_include_total boolean default true/gi) || [];
    assert.equal(optionalTotals.length, 2);
    assert.match(migration, /when coalesce\(p_include_total, true\) then \(select count\(\*\) from base\)/gi);
    const lazyBases = migration.match(/with base as not materialized/gi) || [];
    assert.equal(lazyBases.length, 2, 'pagination must not materialize every match when total is skipped');
    assert.match(migration, /\(b\.name_sort, b\.id\) > \(v_cursor_name, v_cursor_id\)/i);
    assert.match(migration, /\(b\.created_at, b\.id\) < \(v_cursor_created, v_cursor_id\)/i);
    assert.match(migration, /limit p_limit \+ 1/gi);
    assert.doesNotMatch(migration, /\boffset\b/i);
    const cardMarkers = migration.match(/'_card_summary', true/gi) || [];
    assert.equal(cardMarkers.length, 2);
    assert.match(migration, /'ticket_count', \([\s\S]*from public\.tickets t[\s\S]*t\.customer_id = p\.id/i);
    assert.match(migration, /t\.repair_end_at/i);
    assert.match(migration, /t\.budget_status/i);
    assert.doesNotMatch(migration, /t\.photos_urls|t\.checklist_data|t\.checklist_final_data/i);
});

test('linking snapshots legacy ticket fields and blocks technician/tester reassignment', () => {
    assert.match(migration, /new\.customer_id is distinct from old\.customer_id/i);
    assert.match(migration, /not \(coalesce\(v_ctx\.is_admin, false\) or coalesce\(v_ctx\.is_attendant, false\)\)[\s\S]*nao pode trocar o cliente da OS/i);
    assert.match(migration, /new\.client_name := v_customer\.name/i);
    assert.match(migration, /new\.contact_info := coalesce\(\s*nullif\(btrim\(new\.contact_info\), ''\)/i);
    assert.match(migration, /c\.workspace_id = v_ctx\.workspace_id/i);
    assert.match(migration, /c\.deleted_at is null/i);
});

test('direct Data API writes receive the same customer validation as the save RPC', () => {
    assert.match(migration, /new\.person_type not in \('person', 'company'\)/i);
    assert.match(migration, /length\(new\.name\) > 200/i);
    assert.match(migration, /length\(coalesce\(new\.email, ''\)\) > 254/i);
    assert.match(migration, /length\(coalesce\(new\.notes, ''\)\) > 10000/i);
    assert.match(migration, /new\.address_line := nullif\(btrim\(new\.address_line\), ''\)/i);
});

test('customer page carries editable public fields and searches across them', () => {
    for (const field of [
        'state_registration', 'birth_date', 'postal_code', 'address_line',
        'address_number', 'address_complement', 'neighborhood', 'country', 'notes'
    ]) {
        assert.match(migration, new RegExp(`c\\.${field}`));
    }
    assert.doesNotMatch(migration, /select[\s\S]{0,500}c\.created_by/i);
});

test('rollback removes only the feature and preserves OS snapshots', () => {
    assert.match(rollback, /drop function if exists public\.get_customer_page/i);
    assert.match(rollback, /get_customer_page\(text, integer, jsonb, boolean\)/i);
    assert.match(rollback, /get_customer_ticket_page\(uuid, text, integer, jsonb, boolean\)/i);
    assert.match(rollback, /drop trigger if exists aida_enforce_ticket_customer_link on public\.tickets/i);
    assert.match(rollback, /drop constraint if exists tickets_workspace_customer_fkey/i);
    assert.match(rollback, /drop column if exists customer_id/i);
    assert.match(rollback, /drop table if exists public\.customers/i);
    assert.doesNotMatch(rollback, /\bdelete from public\.tickets\b|\btruncate\b/i);
    assert.doesNotMatch(rollback, /drop column if exists client_name|drop column if exists contact_info/i);
});
