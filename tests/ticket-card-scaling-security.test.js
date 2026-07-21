const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const migration = fs.readFileSync(path.join(root, 'optimize_ticket_card_queries.sql'), 'utf8');
const rollback = fs.readFileSync(path.join(root, 'rollback_ticket_card_queries.sql'), 'utf8');
const main = fs.readFileSync(path.join(root, 'js', 'main.js'), 'utf8');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');

test('card RPC derives the tenant from the actor and keeps ticket RLS active', () => {
    assert.match(migration, /security invoker/i);
    assert.match(migration, /get_current_actor_context\(\)/);
    assert.match(migration, /t\.workspace_id = v_ctx\.workspace_id/);
    assert.doesNotMatch(migration, /p_workspace_id/i);
    assert.match(migration, /revoke all on function public\.get_ticket_cards_page[\s\S]*from public/i);
    assert.match(migration, /grant execute on function public\.get_ticket_cards_page[\s\S]*to anon, authenticated/i);
});

test('card RPC uses bounded keyset pagination instead of OFFSET', () => {
    assert.match(migration, /p_limit < 1 or p_limit > 50/i);
    assert.match(migration, /p_cursor jsonb/i);
    assert.match(migration, /\(b\.priority_rank, b\.effective_sort_at, b\.deadline_sort_at, b\.created_at, b\.id\)[\s\S]*>/i);
    assert.doesNotMatch(migration, /\boffset\b/i);
    assert.match(migration, /limit p_limit \+ 1/i);
});

test('card payload omits large modal-only fields and modal reloads the full OS', () => {
    assert.doesNotMatch(migration, /t\.photos_urls/);
    assert.doesNotMatch(migration, /t\.checklist_data/);
    assert.doesNotMatch(migration, /t\.checklist_final_data/);
    assert.match(migration, /'_card_summary', true/);
    assert.match(main, /ticket\._card_summary/);
    assert.match(main, /fetchTicketDetails/);
    assert.match(main, /openPurchaseModal[\s\S]*ensureCompleteTicket/);
    assert.match(main, /openOutcomeModal[\s\S]*ensureCompleteTicket/);
});

test('boards expose independent totals and load-more controls per status', () => {
    assert.match(main, /ticketColumnPagination: \{\}/);
    assert.match(main, /loadMoreTicketColumn\(status\)/);
    assert.match(main, /getTicketColumnCountLabel/);
    assert.match(html, /hasMoreTicketColumn\(status\)/);
    assert.match(html, /Carregar mais OS/);
});

test('rollback removes only the new read API', () => {
    assert.match(rollback, /drop function if exists public\.get_ticket_cards_page/);
    assert.doesNotMatch(rollback, /drop table|delete from|truncate/i);
});
