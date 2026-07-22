const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const migration = fs.readFileSync(path.join(root, 'optimize_schedule_management_queries.sql'), 'utf8');
const rollback = fs.readFileSync(path.join(root, 'rollback_schedule_management_queries.sql'), 'utf8');
const main = fs.readFileSync(path.join(root, 'js', 'main.js'), 'utf8');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');

test('schedule queue RPC derives the tenant, requires admin and keeps RLS active', () => {
    assert.match(migration, /security invoker/i);
    assert.match(migration, /get_current_actor_context\(\)/);
    assert.match(migration, /if not v_ctx\.is_admin/i);
    assert.match(migration, /t\.workspace_id = v_ctx\.workspace_id/);
    assert.doesNotMatch(migration, /p_workspace_id/i);
    assert.match(migration, /revoke all on function public\.get_unscheduled_ticket_page[\s\S]*from public/i);
    assert.match(migration, /grant execute on function public\.get_unscheduled_ticket_page[\s\S]*to anon, authenticated/i);
});

test('schedule queues use bounded keyset pages instead of OFFSET', () => {
    assert.match(migration, /p_limit < 1 or p_limit > 50/i);
    assert.match(migration, /p_cursor jsonb/i);
    assert.match(migration, /\(b\.entry_date, b\.id\) < \(v_cursor_entry, v_cursor_id\)/i);
    assert.doesNotMatch(migration, /\boffset\b/i);
    assert.match(migration, /limit p_limit \+ 1/i);
});

test('front loads each schedule queue independently and offers load more', () => {
    assert.match(main, /unscheduledPages:/);
    assert.match(main, /loadUnscheduledBucket\(bucket/);
    assert.match(main, /loadMoreUnscheduledBucket\(bucket\)/);
    assert.match(main, /loadMorePendingTickets\(\)/);
    assert.match(main, /rpc\/get_unscheduled_ticket_page/);
    assert.doesNotMatch(main, /rpc\/get_unscheduled_tickets[\s\S]{0,400}p_limit:\s*100/);
    assert.match(html, /loadMoreUnscheduledBucket\('assigned'\)/);
    assert.match(html, /loadMoreUnscheduledBucket\('unassigned'\)/);
    assert.match(html, /loadMoreUnscheduledBucket\('conflict'\)/);
    assert.match(html, /loadMoreUnscheduledBucket\('late'\)/);
    assert.match(html, /loadMorePendingTickets\(\)/);
});

test('rollback removes only the new read API and supporting index', () => {
    assert.match(rollback, /drop function if exists public\.get_unscheduled_ticket_page/);
    assert.match(rollback, /drop index if exists public\.idx_tickets_schedule_queue/);
    assert.doesNotMatch(rollback, /drop table|delete from|truncate/i);
});
