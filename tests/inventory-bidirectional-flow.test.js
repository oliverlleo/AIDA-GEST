const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const read = name => fs.readFileSync(path.join(root, name), 'utf8');
const sql = read('inventory_bidirectional_flow.sql');
const rollback = read('rollback_inventory_bidirectional_flow.sql');
const main = read('js/main.js');
const html = read('index.html');

test('enabled inventory adapts legacy ticket parts and opens structured purchase or receipt', () => {
    assert.match(main, /openInventoryPartRequest\(ticket, 'direct_repair', true, 'openInventoryPurchaseAfterAdapt'/);
    assert.match(main, /open_purchase_count/);
    assert.match(main, /Receber Peças/);
    assert.match(main, /refreshPostMutation\(true\)[\s\S]*fetchGlobalLogs/);
    assert.match(html, /handleTicketPartsAction\(ticket\)/);
    assert.match(html, /inventoryTicketPurchases/);
    assert.match(html, /chooseInventoryTicketPurchase\(purchase\)/);
});

test('disabled inventory converts open structured work to the legacy flow atomically', () => {
    assert.match(sql, /create or replace function private\.inventory_convert_open_work_to_legacy/);
    assert.match(sql, /pg_advisory_xact_lock/);
    assert.match(sql, /movement_type[\s\S]*'release'/);
    assert.match(sql, /status = 'cancelled'[\s\S]*inventory_purchases/);
    assert.match(sql, /status = 'cancelled'[\s\S]*ticket_part_items/);
    assert.match(sql, /parts_status = case[\s\S]*then 'Comprado'[\s\S]*else 'Pendente'/);
    assert.match(sql, /Adaptou Controle de Peças/);
    assert.doesNotMatch(sql, /delete\s+from\s+public\.(inventory|ticket)/i);
});

test('bidirectional migration keeps tenant and execution security boundaries', () => {
    assert.match(sql, /get_current_actor_context\(\)/);
    assert.match(sql, /v_ctx\.workspace_id is distinct from p_workspace_id/);
    assert.match(sql, /not coalesce\(v_ctx\.is_admin, false\)/);
    assert.match(sql, /security definer[\s\S]*set search_path = ''/);
    assert.match(sql, /revoke all on function private\.inventory_convert_open_work_to_legacy\(uuid\)[\s\S]*from public, anon, authenticated/);
    assert.doesNotMatch(sql, /create or replace function public\.[^(]+\([^)]*p_workspace_id\s+uuid/i);
});

test('inventory card summary distinguishes pending purchase from awaiting receipt', () => {
    assert.match(sql, /ordered_quantity/);
    assert.match(sql, /open_purchase_count/);
    assert.match(sql, /open_purchase_ids/);
    assert.match(sql, /'awaiting_receipt'/);
    assert.match(sql, /'awaiting_purchase'/);
});

test('rollback restores the previous blocking trigger and legacy summary', () => {
    assert.match(rollback, /drop function if exists private\.inventory_convert_open_work_to_legacy/);
    assert.match(rollback, /Nao e possivel desativar o Estoque/);
    assert.match(rollback, /create or replace function public\.get_ticket_inventory_summaries/);
});