const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const migration = fs.readFileSync(path.join(root, 'optimize_test_bench_queries.sql'), 'utf8');
const rollback = fs.readFileSync(path.join(root, 'rollback_test_bench_queries.sql'), 'utf8');
const queryService = fs.readFileSync(path.join(root, 'js', 'modules', 'ticket-query-service.js'), 'utf8');
const main = fs.readFileSync(path.join(root, 'js', 'main.js'), 'utf8');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');

test('test bench derives the tenant and preserves ticket RLS', () => {
    assert.match(migration, /security invoker/i);
    assert.match(migration, /get_current_actor_context\(\)/);
    assert.match(migration, /t\.workspace_id = v_ctx\.workspace_id/);
    assert.doesNotMatch(migration, /p_workspace_id/i);
    assert.match(migration, /revoke all on function public\.get_test_bench_page[\s\S]*from public/i);
    assert.match(migration, /grant execute on function public\.get_test_bench_page[\s\S]*to anon, authenticated/i);
});

test('test bench reads only final-test cards and omits modal-only fields', () => {
    assert.match(migration, /t\.status = 'Teste Final'/);
    assert.match(migration, /'_card_summary', true/);
    assert.doesNotMatch(migration, /t\.photos_urls|t\.checklist_data|t\.checklist_final_data|t\.tech_notes/);
});

test('test bench order follows priority, deadline, test entry and creation', () => {
    assert.match(migration, /p_use_priority[\s\S]*priority_requested is true then 0/i);
    assert.match(migration, /deadline_rank[\s\S]*deadline_sort_at[\s\S]*test_rank[\s\S]*test_sort_at[\s\S]*created_at/i);
    assert.match(migration, /b\.priority_rank, b\.deadline_rank, b\.deadline_sort_at,[\s\S]*b\.test_rank, b\.test_sort_at, b\.created_at, b\.id/i);
});

test('test bench uses bounded keyset pages without OFFSET', () => {
    assert.match(migration, /p_limit < 1 or p_limit > 50/i);
    assert.match(migration, /p_cursor jsonb/i);
    assert.match(migration, /p_limit \+ 1/i);
    assert.doesNotMatch(migration, /\boffset\b/i);
    assert.match(migration, /idx_tickets_test_bench_queue/);
});

test('tester view uses the dedicated page and exposes total and load more', () => {
    assert.match(queryService, /state\.view === 'tester_bench'[\s\S]*rpc\/get_test_bench_page/);
    assert.match(queryService, /state\.testerBenchPagination\.nextCursor/);
    assert.match(main, /result\.mode === 'test_bench_page'/);
    assert.match(main, /existingIds[\s\S]*result\.data\.filter/);
    assert.match(html, /testerBenchPagination\.total/);
    assert.match(html, /loadMoreTesterBench\(\)/);
    assert.match(html, /Carregar mais OS/);
});

test('rollback removes only the new test-bench read objects', () => {
    assert.match(rollback, /drop function if exists public\.get_test_bench_page/);
    assert.match(rollback, /drop index if exists public\.idx_tickets_test_bench_queue/);
    assert.doesNotMatch(rollback, /drop table|delete from|truncate/i);
});
