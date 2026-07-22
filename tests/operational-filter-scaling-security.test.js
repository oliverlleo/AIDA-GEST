const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const migration = fs.readFileSync(path.join(root, 'optimize_operational_filter_queries.sql'), 'utf8');
const rollback = fs.readFileSync(path.join(root, 'rollback_operational_filter_queries.sql'), 'utf8');
const queryService = fs.readFileSync(path.join(root, 'js', 'modules', 'ticket-query-service.js'), 'utf8');
const main = fs.readFileSync(path.join(root, 'js', 'main.js'), 'utf8');

test('operational page derives the tenant and keeps ticket RLS active', () => {
    assert.match(migration, /security invoker/i);
    assert.match(migration, /get_current_actor_context\(\)/);
    assert.match(migration, /t\.workspace_id = v_ctx\.workspace_id/);
    assert.doesNotMatch(migration, /p_workspace_id/i);
    assert.match(migration, /revoke all on function public\.get_operational_ticket_page[\s\S]*from public/i);
    assert.match(migration, /grant execute on function public\.get_operational_ticket_page[\s\S]*to anon, authenticated/i);
});

test('operational page is bounded and uses a complete keyset cursor', () => {
    assert.match(migration, /p_limit < 0 or p_limit > 50/i);
    assert.match(migration, /p_cursor jsonb/i);
    assert.match(migration, /ot\.due_is_null, ot\.due_sort, ot\.requested_rank,[\s\S]*ot\.priority_rank, ot\.created_at, ot\.id[\s\S]*>/i);
    assert.doesNotMatch(migration, /\boffset\b/i);
    assert.match(migration, /p_limit \+ 1/i);
});

test('operational cards omit large modal-only fields', () => {
    assert.doesNotMatch(migration, /t\.photos_urls/);
    assert.doesNotMatch(migration, /t\.checklist_data/);
    assert.doesNotMatch(migration, /t\.checklist_final_data/);
    assert.match(migration, /'_card_summary', true/);
});

test('filtered Kanban and counts use the cursor RPC instead of OFFSET', () => {
    assert.match(queryService, /rpc\/get_operational_ticket_page/);
    assert.match(queryService, /p_cursor:/);
    assert.match(queryService, /p_include_counts:/);
    assert.match(main, /ticketPagination\.nextCursor/);
    assert.match(main, /result\.hasMore/);
    assert.doesNotMatch(queryService, /OPERATIONAL QUEUE RPC[\s\S]{0,1500}p_offset/i);
});

test('rollback removes only the new read API', () => {
    assert.match(rollback, /drop function if exists public\.get_operational_ticket_page/);
    assert.doesNotMatch(rollback, /drop table|drop index|delete from|truncate/i);
});
