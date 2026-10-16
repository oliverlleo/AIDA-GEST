// Run from the task workspace after preparing a synthetic database. Never production.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import { execFileSync, spawn } from 'node:child_process';

const root = process.cwd();
const database = process.env.AIDA_CONCURRENCY_TEST_DATABASE || 'aida_auth_review_concurrency_http_20261016';
assert.match(database, /^aida_auth_review_concurrency_[a-zA-Z0-9_]+$/);
const password = fs.readFileSync(path.join(root, 'work/pg-test-password.txt'), 'utf8').trim();
const secret = fs.readFileSync(path.join(root, 'work/postgrest-jwt-secret.txt'), 'utf8').trim();
const psql = path.join(root, 'work/tools/pg17/pgsql/bin/psql.exe');
const args = ['-h', '127.0.0.1', '-p', '54329', '-U', 'aida_test_admin', '-d', database, '-v', 'ON_ERROR_STOP=1', '-qAt'];
const env = { ...process.env, PGPASSWORD: password };
const sql = query => execFileSync(psql, [...args, '-c', query], { env, encoding: 'utf8' }).trim();
assert.equal(sql('SELECT current_database()'), database);
assert.equal(sql("SELECT host(inet_server_addr())||':'||inet_server_port()"), '127.0.0.1:54329');
assert.equal(sql("SELECT to_regprocedure('private.enforce_ticket_revision()') IS NOT NULL"), 't');
const workspace = '20000000-0000-4000-8000-000000000002';
const ticket = '50000000-0000-4000-8000-000000000001';
const analysisTicket = '50000000-0000-4000-8000-000000000005';
const uid = n => '10000000-0000-4000-8000-' + String(n).padStart(12, '0');
const sid = n => '99400000-0000-4000-8000-' + String(n).padStart(12, '0');
sql(`INSERT INTO auth.sessions(id,user_id,created_at) SELECT ('99400000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,('10000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,clock_timestamp() FROM generate_series(1,8)n ON CONFLICT DO NOTHING; DELETE FROM private.request_budgets;`);
function jwt(n) {
    const now = Math.floor(Date.now() / 1000);
    const header = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url');
    const body = Buffer.from(JSON.stringify({ role: 'authenticated', sub: uid(n), session_id: sid(n), iat: now - 1, exp: now + 3600, aud: 'authenticated' })).toString('base64url');
    return header + '.' + body + '.' + crypto.createHmac('sha256', secret).update(header + '.' + body).digest('base64url');
}
const endpoint = 'http://127.0.0.1:54332';
async function request(route, { actor = 2, method = 'GET', body, version, operationVersion, selectedWorkspace = workspace } = {}) {
    const response = await fetch(endpoint + route, { method, headers: {
        Authorization: 'Bearer ' + jwt(actor), 'x-workspace-id': selectedWorkspace,
        Prefer: 'return=representation', 'Content-Type': 'application/json',
        ...(version ? { 'x-aida-ticket-version': JSON.stringify(version) } : {}),
        ...(operationVersion ? { 'x-aida-operation-version': JSON.stringify(operationVersion) } : {})
    }, ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
    const raw = await response.text();
    let data; try { data = JSON.parse(raw); } catch { data = raw; }
    return { status: response.status, data };
}
const results = [];
const record = (name, result, expected) => {
    assert.equal(result.status, expected, name + ': ' + JSON.stringify(result));
    results.push({ test: name, status: result.status, code: result.data?.code, passed: true });
};
async function withRowLocked(id, callback, table = 'tickets') {
    assert.ok(['tickets', 'internal_notes', 'inventory_purchases', 'ticket_appointments'].includes(table));
    const worker = spawn(psql, args, { env, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
    let output = '', errors = '', timer;
    const exited = new Promise((resolve, reject) => {
        worker.once('error', reject);
        worker.once('exit', code => code === 0 ? resolve() : reject(new Error(errors)));
    });
    worker.stderr.on('data', data => { errors += data; });
    const ready = new Promise((resolve, reject) => {
        timer = setTimeout(() => reject(new Error('Lock readiness timeout: ' + errors)), 10000);
        worker.stdout.on('data', data => { output += data; if (output.includes('ROW_LOCK_HELD')) { clearTimeout(timer); resolve(); } });
    });
    worker.stdin.write(`BEGIN; SELECT id FROM public.${table} WHERE id='${id}' FOR UPDATE; SELECT 'ROW_LOCK_HELD';\n`);
    try { await ready; await callback(); }
    finally { clearTimeout(timer); worker.stdin.end('COMMIT;\n\\q\n'); await exited; }
}
async function observeWaitingRequests() {
    const deadline = Date.now() + 8000;
    while (Date.now() < deadline) {
        const count = Number(sql("SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND wait_event_type='Lock' AND (query ILIKE '%tickets%' OR query ILIKE '%start_ticket_analysis%' OR query ILIKE '%set_note_check_status%' OR query ILIKE '%receive_inventory_purchase%' OR query ILIKE '%reschedule_ticket_appointment%')"));
        if (count >= 2) return;
        await new Promise(resolve => setTimeout(resolve, 25));
    }
    throw new Error('Two actual HTTP requests did not contend for the row lock');
}
const server = spawn(path.join(root, 'work/tools/postgrest/postgrest.exe'), [], { windowsHide: true, stdio: ['ignore', 'ignore', 'pipe'], env: {
    ...env, PATH: path.join(root, 'work/tools/pg17/pgsql/bin') + path.delimiter + env.PATH,
    PGRST_DB_URI: 'postgresql://aida_test_admin:' + encodeURIComponent(password) + '@127.0.0.1:54329/' + database,
    PGRST_DB_SCHEMAS: 'public', PGRST_DB_ANON_ROLE: 'anon', PGRST_JWT_SECRET: secret,
    PGRST_SERVER_HOST: '127.0.0.1', PGRST_SERVER_PORT: '54332', PGRST_DB_TX_END: 'commit',
    PGRST_DB_PRE_REQUEST: 'private.check_request_budget', PGRST_DB_MAX_ROWS: '1000', PGRST_DB_POOL: '10', PGRST_LOG_LEVEL: 'error'
} });
let serverErrors = '';
server.stderr.on('data', data => { serverErrors += data; });
server.on('error', error => { serverErrors += error.message; });
try {
    let ready = false;
    for (let i = 0; i < 50 && !ready; i++) {
        try { ready = (await request('/tickets?select=id&limit=1')).status === 200; } catch { /* startup */ }
        if (!ready) await new Promise(resolve => setTimeout(resolve, 100));
    }
    assert.ok(ready, 'Local PostgREST did not start: ' + serverErrors);
    const initial = await request('/tickets?select=id,revision,tech_notes&id=eq.' + ticket);
    record('authenticated snapshot includes server revision', initial, 200);
    let revision = initial.data[0].revision;
    assert.ok(Number.isSafeInteger(revision) && revision > 0);
    const version = { id: ticket, revision };
    for (const [name, supplied] of [ ['missing version', undefined], ['stale revision', { ...version, revision: revision + 10 }], ['other ticket version', { ...version, id: analysisTicket }] ]) {
        record(name + ' rejected', await request('/tickets?id=eq.' + ticket, { method: 'PATCH', body: { tech_notes: 'REJECTED' }, version: supplied }), 409);
    }
    record('browser cannot assign its own server revision', await request('/tickets?id=eq.' + ticket, { method: 'PATCH', body: { revision: revision + 100 }, version }), 403);
    assert.equal(Number(sql(`SELECT revision FROM public.tickets WHERE id='${ticket}'`)), revision);
    let racing;
    await withRowLocked(ticket, async () => {
        racing = Promise.all([2, 8].map(actor => request('/tickets?id=eq.' + ticket, { actor, method: 'PATCH', body: { tech_notes: 'HTTP contender ' + actor }, version })));
        await observeWaitingRequests();
    });
    const contenders = await racing;
    assert.deepEqual(contenders.map(result => result.status).sort(), [200, 409]);
    const winner = contenders.find(result => result.status === 200).data[0];
    assert.equal(winner.revision, revision + 1);
    assert.equal(sql(`SELECT tech_notes FROM public.tickets WHERE id='${ticket}'`), winner.tech_notes);
    contenders.forEach((result, i) => record('simultaneous editor ' + (i + 1), result, result.status));
    results.push({ test: 'two real HTTP sessions waited on the same row; exactly one committed; revision advanced once', passed: true });
    record('retry of already committed snapshot is rejected', await request('/tickets?id=eq.' + ticket, { method: 'PATCH', body: { tech_notes: 'RETRY REJECTED' }, version }), 409);
    revision = winner.revision;
    const reviewed = await request('/tickets?id=eq.' + ticket, { method: 'PATCH', body: { tech_notes: 'Reviewed current snapshot' }, version: { id: ticket, revision } });
    record('reviewed current revision saves normally', reviewed, 200);
    assert.equal(reviewed.data[0].revision, revision + 1);
    record('wrong workspace remains denied despite a real revision', await request('/tickets?id=eq.' + ticket, { selectedWorkspace: '20000000-0000-4000-8000-000000000001', method: 'PATCH', body: { tech_notes: 'WRONG TENANT' }, version: { id: ticket, revision: revision + 1 } }), 403);
    record('missing version cannot hard delete a ticket', await request('/tickets?id=eq.' + ticket, { method: 'DELETE' }), 409);
    sql(`SELECT test_auth.login(2,'${workspace}','${sid(2)}'); UPDATE public.tickets SET status='Analise Tecnica',analysis_started_at=NULL WHERE id='${analysisTicket}';`);
    const logCount = Number(sql(`SELECT count(*) FROM public.ticket_logs WHERE ticket_id='${analysisTicket}' AND action=('Iniciou An'||chr(225)||'lise')`));
    let starts;
    await withRowLocked(analysisTicket, async () => {
        starts = Promise.all([2, 8].map(actor => request('/rpc/start_ticket_analysis', { actor, method: 'POST', body: { p_ticket_id: analysisTicket } })));
        await observeWaitingRequests();
    });
    const started = await starts;
    assert.deepEqual(started.map(result => result.status).sort(), [200, 400]);
    assert.equal(Number(sql(`SELECT count(*) FROM public.ticket_logs WHERE ticket_id='${analysisTicket}' AND action=('Iniciou An'||chr(225)||'lise')`)), logCount + 1);
    results.push({ test: 'simultaneous start-analysis commands keep one effect and one history entry under row lock', passed: true });
    const note = '6c000000-0000-4000-8000-000000000002';
    sql(`SELECT test_auth.login(2,'${workspace}','${sid(2)}'); INSERT INTO public.internal_notes(id,workspace_id,author_id,author_name,content,checklist_data) VALUES('${note}','${workspace}','${uid(2)}','Synthetic owner','HTTP note fixture','[{"item":"A","ok":false},{"item":"B","ok":false}]') ON CONFLICT(id) DO UPDATE SET checklist_data=EXCLUDED.checklist_data;`);
    let checks;
    await withRowLocked(note, async () => {
        checks = Promise.all([0, 1].map(index => request('/rpc/set_note_check_status', {
            actor: index ? 8 : 2, method: 'POST',
            body: { p_note_id: note, p_item_index: index, p_item_text: index ? 'B' : 'A', p_expected_ok: false, p_new_ok: true }
        })));
        await observeWaitingRequests();
    }, 'internal_notes');
    for (const result of await checks) record('simultaneous independent checklist item', result, 200);
    assert.deepEqual(JSON.parse(sql(`SELECT checklist_data FROM public.internal_notes WHERE id='${note}'`)), [{ item: 'A', ok: true }, { item: 'B', ok: true }]);
    record('repeating a checkbox desired-state command stays checked', await request('/rpc/set_note_check_status', {
        method: 'POST', body: { p_note_id: note, p_item_index: 0, p_item_text: 'A', p_expected_ok: false, p_new_ok: true }
    }), 200);
    assert.equal(sql(`SELECT checklist_data->0->>'ok' FROM public.internal_notes WHERE id='${note}'`), 'true');
    results.push({ test: 'two checklist writers preserve both items under a real lock; identical retry does not toggle twice', passed: true });
    const purchase = '94cb3619-0000-4000-8000-000000000012';
    const purchaseItem = '94cb3619-0000-4000-8000-000000000013';
    const item = '94cb3619-0000-4000-8000-000000000010';
    const location = '94cb3619-0000-4000-8000-000000000011';
    const detail = await request('/rpc/get_inventory_purchase_detail', { method: 'POST', body: { p_purchase_id: purchase } });
    record('purchase detail supplies its own revision', detail, 200);
    const purchaseVersion = { resource: 'inventory_purchases', id: purchase, revision: detail.data.purchase.revision };
    const receiveBody = { p_purchase_id: purchase, p_receipts: [{ purchase_item_id: purchaseItem, quantity: 2, unit_cost: 2, destination: 'stock', location_id: location }], p_confirm_allocation: false };
    record('partial receipt without original purchase revision is rejected', await request('/rpc/receive_inventory_purchase', { method: 'POST', body: receiveBody }), 409);
    assert.equal(Number(sql(`SELECT received_quantity FROM public.inventory_purchase_items WHERE id='${purchaseItem}'`)), 0);
    let receipts;
    await withRowLocked(purchase, async () => {
        receipts = Promise.all([2, 8].map(actor => request('/rpc/receive_inventory_purchase', { actor, method: 'POST', body: receiveBody, operationVersion: purchaseVersion })));
        await observeWaitingRequests();
    }, 'inventory_purchases');
    const received = await receipts;
    assert.deepEqual(received.map(result => result.status).sort(), [200, 409]);
    for (const result of received) record('simultaneous partial receipt', result, result.status);
    assert.equal(Number(sql(`SELECT received_quantity FROM public.inventory_purchase_items WHERE id='${purchaseItem}'`)), 2);
    assert.equal(Number(sql(`SELECT physical_quantity FROM public.inventory_balances WHERE item_id='${item}' AND location_id='${location}'`)), 2);
    assert.equal(Number(sql(`SELECT count(*) FROM public.inventory_movements WHERE item_id='${item}'`)), 1);
    results.push({ test: 'partial receipt adds two units once, with one movement; stale contender rolls back every side effect', passed: true });
    const appointment = '94cb3619-0000-4000-8000-000000000021';
    const appointmentVersion = { resource: 'ticket_appointments', id: appointment, revision: Number(sql(`SELECT revision FROM public.ticket_appointments WHERE id='${appointment}'`)) };
    const scheduleBody = { p_appointment_id: appointment, p_technician_id: sql("SELECT id FROM test_auth.fixture WHERE name='rejoined_employee'"),
        p_scheduled_start: sql("SELECT ((current_date+31+time '11:00') AT TIME ZONE 'America/Sao_Paulo')::text"),
        p_scheduled_end: sql("SELECT ((current_date+31+time '11:30') AT TIME ZONE 'America/Sao_Paulo')::text"), p_notes: 'HTTP controlled remapping' };
    record('reschedule without original appointment revision is rejected', await request('/rpc/reschedule_ticket_appointment', { method: 'POST', body: scheduleBody }), 409);
    let schedules;
    await withRowLocked(appointment, async () => {
        schedules = Promise.all([2, 8].map(actor => request('/rpc/reschedule_ticket_appointment', { actor, method: 'POST', body: scheduleBody, operationVersion: appointmentVersion })));
        await observeWaitingRequests();
    }, 'ticket_appointments');
    const scheduled = await schedules;
    assert.deepEqual(scheduled.map(result => result.status).sort(), [200, 409]);
    for (const result of scheduled) record('simultaneous reschedule', result, result.status);
    assert.equal(Number(sql(`SELECT revision FROM public.ticket_appointments WHERE id='${appointment}'`)), appointmentVersion.revision + 1);
    results.push({ test: 'one appointment reschedule commits; stale contender cannot overwrite it', passed: true });
    fs.writeFileSync(path.join(root, 'outputs/concorrencia-http-local.json'), JSON.stringify({ environment: 'local synthetic PostgreSQL 17 + PostgREST 16 COMMIT, loopback only', database, checks: results.length, results }, null, 2));
    console.log(JSON.stringify({ checks: results.length, passed: true, output: 'outputs/concorrencia-http-local.json' }));
} finally {
    // Stop only the exact child helper created by this script, never user apps/services.
    server.kill();
}
