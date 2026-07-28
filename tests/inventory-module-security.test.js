const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const read = (name) => fs.readFileSync(path.join(root, name), 'utf8');
const foundation = read('inventory_module_foundation.sql');
const workflow = read('inventory_workflow_integration.sql');
const purchases = read('inventory_purchase_and_consumption.sql');
const operations = read('inventory_operations.sql');
const creationCatalog = read('inventory_creation_catalog.sql');
const returns = read('inventory_returns.sql');
const rollback = read('rollback_inventory_module.sql');
const locationImages = read('inventory_location_and_images.sql');
const schemeManagement = read('inventory_location_scheme_management.sql');
const locationImagesRollback = read('rollback_inventory_location_and_images.sql');
const schemeManagementRollback = read('rollback_inventory_location_scheme_management.sql');

test('inventory tables are tenant-bound, protected by RLS and closed to direct Data API writes', () => {
    const tables = [
        'inventory_items', 'inventory_item_costs', 'inventory_location_schemes',
        'inventory_locations', 'inventory_balances', 'inventory_item_models',
        'inventory_item_suppliers', 'inventory_item_relations', 'ticket_part_items',
        'inventory_reservations', 'inventory_purchases', 'inventory_purchase_items',
        'inventory_purchase_allocations', 'inventory_movements'
    ];
    for (const table of tables) {
        assert.match(foundation, new RegExp(`alter table public\\.${table} enable row level security`, 'i'));
    }
    assert.match(foundation, /revoke all on table[\s\S]*public\.inventory_items[\s\S]*from public, anon, authenticated/i);
    assert.match(foundation, /workspace_id uuid not null/i);
    assert.doesNotMatch(
        [foundation, workflow, purchases, operations, creationCatalog, returns].join('\n'),
        /create or replace function public\.[^(]+\([^)]*p_workspace_id\s+uuid/i
    );
});

test('critical functions derive actor context and use a fixed search path', () => {
    const sql = [foundation, workflow, purchases, operations, creationCatalog, returns].join('\n');
    assert.match(sql, /get_current_actor_context\(\)/i);
    assert.match(sql, /private\.inventory_assert_access/i);
    const publicDefiners = sql.match(/create or replace function public\.[\s\S]*?security definer[\s\S]*?set search_path = ''/gi) || [];
    assert.ok(publicDefiners.length >= 15);
    assert.match(creationCatalog, /inventory_assert_access\(v_ctx\.workspace_id, 'manage'\)/i);
    assert.match([foundation, workflow, purchases].join('\\n'), /v_ticket\.technician_id is distinct from v_ctx\.actor_employee_id/i);
});

test('balance and reservation invariants are enforced in transactional SQL', () => {
    assert.match(foundation, /reserved_quantity <= physical_quantity/i);
    assert.match(foundation, /available_quantity[\s\S]*generated always as \(physical_quantity - reserved_quantity\) stored/i);
    assert.match(workflow, /for update of b/i);
    assert.match(workflow, /least\(v_missing, v_balance\.available_quantity\)/i);
    assert.match(purchases, /for update of r/i);
    assert.match(purchases, /v_used is null or v_used < 0 or v_used > v_remaining/i);
    assert.match(purchases, /A quantidade usada nao pode exceder a reserva/i);
});

test('movements are immutable and corrections create new audited movements', () => {
    assert.match(foundation, /function private\.inventory_movements_immutable/i);
    assert.match(foundation, /before update or delete on public\.inventory_movements/i);
    assert.match(foundation, /Movimentacoes de estoque sao imutaveis/i);
    assert.match(foundation, /insert into public\.inventory_movements/i);
    assert.match(returns, /movement_type[\s\S]*'return'/i);
});

test('module cannot be enabled without parts control or disabled with pending operations', () => {
    assert.match(foundation, /aida_config_bool[\s\S]*'workflow', 'parts_control'/i);
    assert.match(foundation, /aida_config_bool[\s\S]*'modules', 'inventory'/i);
    assert.match(foundation, /Ative o Controle de compra de pecas antes de ativar o Estoque/i);
    assert.match(foundation, /Nao e possivel desativar o Estoque: existem reservas, solicitacoes ou compras abertas/i);
    assert.match(foundation, /trigger aida_validate_inventory_tracker_config/i);
});

test('rollback removes inventory objects without deleting legacy tickets or legacy parts data', () => {
    assert.match(rollback, /drop table if exists public\.inventory_movements/i);
    assert.match(rollback, /drop table if exists public\.inventory_items/i);
    assert.doesNotMatch(rollback, /drop table if exists public\.tickets/i);
    assert.doesNotMatch(rollback, /delete from public\.tickets/i);
    assert.doesNotMatch(rollback, /drop column if exists parts_needed/i);
    assert.doesNotMatch(rollback, /drop column if exists supplier_purchases/i);
});

test('location and image extensions keep actor-derived tenant isolation', () => {
    const sql = [locationImages, schemeManagement].join('\n');
    assert.match(sql, /get_current_actor_context\(\)/i);
    assert.match(sql, /inventory_assert_access\(v_ctx\.workspace_id, 'admin'\)/i);
    assert.doesNotMatch(sql, /p_workspace_id\s+uuid/i);
    assert.match(sql, /security definer[\s\S]*?set search_path\s*=\s*''/i);
    assert.match(locationImages, /inventory_images[\s\S]*storage\.foldername\(name\)/i);
    assert.match(locationImages, /file_size_limit[\s\S]*5242880/i);
    assert.match(locationImages, /image\/jpeg[\s\S]*image\/png[\s\S]*image\/webp/i);
});

test('location extensions include non-destructive rollback scripts', () => {
    assert.match(locationImagesRollback, /drop function if exists public\.set_inventory_item_locations/i);
    assert.match(locationImagesRollback, /not exists \(select 1 from storage\.objects/i);
    assert.match(schemeManagementRollback, /drop function if exists public\.manage_inventory_location_scheme/i);
    assert.doesNotMatch([locationImagesRollback, schemeManagementRollback].join('\n'), /delete from public\.inventory_(items|movements|balances)/i);
});