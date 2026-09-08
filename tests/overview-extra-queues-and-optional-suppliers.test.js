const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');

test('extra overview queues are tenant-bound, paginated and return card-only data', () => {
    const sql = read('fix_overview_extra_queues_and_optional_suppliers.sql');

    assert.match(sql, /create or replace function public\.get_overview_extra_queue_page/i);
    assert.match(sql, /security invoker/i);
    assert.match(sql, /get_current_actor_context\(\)/);
    assert.match(sql, /t\.workspace_id = v_ctx\.workspace_id/);
    assert.doesNotMatch(sql, /p_workspace_id/i);
    assert.match(sql, /p_limit is null or p_limit < 1 or p_limit > 50/i);
    assert.match(sql, /p_cursor jsonb/i);
    assert.match(sql, /p_limit \+ 1/i);
    assert.match(sql, /'pendingTests', 'unscheduledTickets'/);
    assert.match(sql, /w\.status = 'Teste Final'/);
    assert.match(sql, /w\.analysis_scheduled_at is null/);
    assert.match(sql, /w\.repair_scheduled_at is null/);
    assert.match(sql, /jsonb_build_object\(\s*'id', pr\.id/s);
    assert.doesNotMatch(sql, /to_jsonb\(pr\)/);
});

test('manual supplier purchase remains workspace-checked and employee-compatible', () => {
    const sql = read('fix_overview_extra_queues_and_optional_suppliers.sql');
    const purchase = sql.slice(sql.indexOf('create or replace function public.create_inventory_purchase'));

    assert.match(sql, /alter column supplier_id drop not null/i);
    assert.match(purchase, /security definer/i);
    assert.match(purchase, /set search_path = ''/i);
    assert.match(purchase, /perform private\.inventory_assert_access\(v_ctx\.workspace_id, 'manage'\)/);
    assert.match(purchase, /v_supplier_registry_enabled/);
    assert.match(purchase, /p_supplier_name text default null/i);
    assert.match(purchase, /f\.workspace_id = v_ctx\.workspace_id/);
    assert.match(purchase, /grant execute on function public\.create_inventory_purchase[\s\S]*to anon, authenticated/i);
});

test('home screen requests the dedicated queues and presents both controlled cards', () => {
    const main = read('js/main.js');
    const html = read('index.html');

    assert.match(main, /pendingTests: 0, unscheduledTickets: 0/);
    assert.match(main, /rpc\/get_overview_extra_queues/);
    assert.match(main, /rpc\/get_overview_extra_queue_page/);
    assert.match(main, /syncHomeExtraOverviewQueues/);
    assert.match(html, /Aguardando Teste Final/);
    assert.match(html, /openOverviewQueueModal\('pendingTests'\)/);
    assert.match(html, /Sem Agendamento/);
    assert.match(html, /openOverviewQueueModal\('unscheduledTickets'\)/);
    assert.match(html, /isOverviewSectionEnabled\('tests'\) && isFinalTestEnabled\(\)/);
    assert.match(html, /isOverviewSectionEnabled\('unscheduled'\) && isModuleEnabled\('agenda'\)/);
});

test('purchase forms replace the registry with a named supplier only when it is disabled', () => {
    const html = read('index.html');
    const inventory = read('js/modules/inventory-management-service.js');
    const actions = read('js/modules/ticket-actions.js');

    assert.match(html, /Fornecedor da compra \*/);
    assert.match(html, /x-model\.trim="purchaseFlow\.supplierName"/);
    assert.match(html, /x-model\.trim="inventory\.purchaseForm\.supplier_name"/);
    assert.match(inventory, /supplier_registry_enabled !== false/);
    assert.match(inventory, /p_supplier_name: supplierRegistryEnabled \? null : supplierName/);
    assert.match(actions, /const supplierRegistryEnabled = deps\.isModuleEnabled\('suppliers'\)/);
    assert.match(actions, /supplier\?\.whatsapp/);
});
