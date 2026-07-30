const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');

test('purchase captures a validated unit cost without trusting the browser', () => {
    const sql = read('inventory_purchase_cost_reference.sql');
    const purchaseFunction = sql.slice(
        sql.indexOf('create or replace function public.create_inventory_purchase'),
        sql.indexOf('create or replace function public.get_ticket_inventory_budget_cost_summaries')
    );

    assert.match(purchaseFunction, /v_unit_cost numeric\(14,4\)/);
    assert.match(purchaseFunction, /v_unit_cost := \(v_allocation ->> 'unit_cost'\)::numeric/);
    assert.match(purchaseFunction, /v_unit_cost is null or v_unit_cost < 0/);
    assert.match(purchaseFunction, /perform private\.inventory_assert_access\(v_ctx\.workspace_id, 'manage'\)/);
    assert.match(purchaseFunction, /set search_path = ''/);
    assert.match(purchaseFunction, /ordered_quantity, supplier_sku_snapshot, unit_cost/);
    assert.doesNotMatch(purchaseFunction, /update public\.inventory_item_costs/);
});

test('average cost changes on receipt, not on an unreceived or cancelled order', () => {
    const receiptSql = read('inventory_direct_ticket_receipt.sql');
    assert.match(receiptSql, /v_new_average :=/);
    assert.match(receiptSql, /update public\.inventory_item_costs/);
    assert.match(receiptSql, /average_cost = v_new_average/);
    assert.match(receiptSql, /last_cost = v_unit_cost/);
});

test('budget cost APIs are tenant-bound, manager-only, bounded and indexed', () => {
    const sql = read('inventory_purchase_cost_reference.sql');

    assert.match(sql, /get_ticket_inventory_budget_cost_summaries/);
    assert.match(sql, /cardinality\(p_ticket_ids\) > 100/);
    assert.match(sql, /get_ticket_inventory_budget_costs\(p_ticket_id uuid\)/);
    assert.match(sql, /perform private\.inventory_assert_access\(v_ctx\.workspace_id, 'manage'\)/);
    assert.match(sql, /t\.workspace_id = v_ctx\.workspace_id/);
    assert.match(sql, /inventory_purchase_items_item_cost_history_idx/);
    assert.match(sql, /where unit_cost is not null/);
    assert.match(sql, /revoke all on function public\.get_ticket_inventory_budget_costs\(uuid\) from public/);
});

test('frontend asks for cost, reuses history and loads detailed budget costs on demand', () => {
    const service = read('js/modules/inventory-management-service.js');
    const query = read('js/modules/inventory-query-service.js');
    const main = read('js/main.js');
    const html = read('index.html');

    assert.match(service, /unit_cost: number\(item\.unit_cost\)/);
    assert.match(service, /Informe o custo unitário de cada peça selecionada/);
    assert.match(main, /unit_cost: item\.has_cost_history \? Number\(item\.last_cost\) : ''/);
    assert.match(main, /loadTicketInventoryBudgetCosts\(completeTicket\)/);
    assert.match(query, /\.filter\(ticket => ticket\?\.status === 'Aprovacao'\)/);
    assert.match(query, /get_ticket_inventory_budget_cost_summaries/);
    assert.match(html, /Custo unit\. \*/);
    assert.match(html, /Referência de custo das peças/);
    assert.match(html, /Custo das peças/);
});
