const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function target(extra = {}) {
    const events = new Map();
    return Object.assign({
        addEventListener(name, fn) { if (!events.has(name)) events.set(name, new Set()); events.get(name).add(fn); },
        removeEventListener(name, fn) { events.get(name)?.delete(fn); },
        emit(name, value = {}) { for (const fn of events.get(name) || []) fn(value); },
        count() { return [...events.values()].reduce((sum, set) => sum + set.size, 0); }
    }, extra);
}
const settle = async () => { for (let i = 0; i < 8; i++) await Promise.resolve(); };

function runtime(refresh) {
    const timers = new Map(), intervals = new Map(), calls = [], auth = [], removed = [], channels = [];
    let next = 0;
    const doc = target({ visibilityState: 'visible' });
    const win = target({ navigator: { onLine: true } });
    const sandbox = {
        window: win, document: doc, Date, Promise, Set, WeakMap, console,
        setTimeout: (fn, delay) => { const id = ++next; timers.set(id, { fn, delay }); return id; },
        clearTimeout: id => timers.delete(id),
        setInterval: fn => { const id = ++next; intervals.set(id, fn); return id; },
        clearInterval: id => intervals.delete(id)
    };
    vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../js/modules/workspace-sync-service.js'), 'utf8'), sandbox);
    const state = { user: { workspace_id: 'company-a' }, session: { user: { id: 'person-a' }, access_token: 'current-jwt' } };
    const client = {
        realtime: { setAuth: async token => auth.push(token) },
        channel(topic, options) {
            const channel = { topic, options,
                on(type, filter, fn) { this.type = type; this.filter = filter; this.receive = fn; return this; },
                subscribe(fn) { this.status = fn; return this; }
            };
            channels.push(channel); return channel;
        },
        removeChannel: async channel => removed.push(channel)
    };
    const service = win.AIDAWorkspaceSyncService;
    const deps = { client, refresh: refresh || (async scopes => calls.push([...scopes])) };
    return { state, service, client, deps, doc, win, timers, intervals, calls, auth, removed, channels,
        async tick() {
            const nextTimer = timers.entries().next().value;
            if (!nextTimer) return;
            timers.delete(nextTimer[0]); nextTimer[1].fn(); await settle();
        }
    };
}

test('joins one private tenant channel after authenticating and accepts only known invalidations', async () => {
    const r = runtime();
    r.service.start(r.state, r.deps); await settle();
    assert.deepEqual(r.auth, ['current-jwt']);
    assert.equal(r.channels.length, 1);
    assert.equal(r.channels[0].topic, 'workspace:company-a');
    assert.equal(r.channels[0].options.config.private, true);
    assert.equal(r.channels[0].type, 'broadcast');
    r.channels[0].status('SUBSCRIBED'); await r.tick();
    assert.equal(r.calls.length, 1);
    assert.equal(r.calls[0].length, 6);
    r.channels[0].receive({ payload: { scope: 'unknown', new: { secret: 'ignored' } } });
    assert.equal(r.timers.size, 0);
    r.channels[0].receive({ payload: { scope: 'tickets', new: { secret: 'ignored' } } });
    r.channels[0].receive({ payload: { scope: 'tickets' } });
    r.channels[0].receive({ payload: { scope: 'notes' } });
    assert.equal(r.timers.size, 1);
    await r.tick();
    assert.deepEqual(r.calls[1], ['tickets', 'notes']);
    r.service.start(r.state, r.deps); await settle();
    assert.equal(r.channels.length, 1);
});

test('coalesces a burst and runs one follow-up for events received during refresh', async () => {
    let release;
    const calls = [];
    const r = runtime(async scopes => { calls.push([...scopes]); if (calls.length === 1) await new Promise(resolve => { release = resolve; }); });
    r.service.start(r.state, r.deps); await settle();
    r.channels[0].receive({ payload: { scope: 'tickets' } });
    await r.tick();
    assert.equal(calls.length, 1);
    for (let i = 0; i < 20; i++) r.channels[0].receive({ payload: { scope: 'inventory' } });
    assert.equal(r.timers.size, 0);
    release(); await settle();
    assert.equal(r.timers.size, 1);
    assert.ok([...r.timers.values()][0].delay >= 2900, 'continuous events respect the minimum interval');
    await r.tick();
    assert.deepEqual(calls, [['tickets'], ['inventory']]);
});

test('hidden/offline pages wait; focus, reconnect, and the visible fallback catch up', async () => {
    const r = runtime(); r.service.start(r.state, r.deps); await settle();
    r.doc.visibilityState = 'hidden';
    r.channels[0].receive({ payload: { scope: 'tickets' } });
    for (const poll of r.intervals.values()) poll();
    assert.equal(r.timers.size, 0);
    r.doc.visibilityState = 'visible'; r.doc.emit('visibilitychange');
    await r.tick(); assert.equal(r.calls.length, 1);
    r.win.navigator.onLine = false; r.win.emit('offline');
    r.win.emit('focus'); assert.equal(r.timers.size, 0);
    r.win.navigator.onLine = true; r.win.emit('online');
    await r.tick(); assert.equal(r.calls.length, 2);
    r.channels[0].status('CHANNEL_ERROR');
    assert.equal(r.state.syncStatus, 'reconnecting');
    r.channels[0].status('SUBSCRIBED');
    await r.tick(); assert.equal(r.calls.length, 3);
    for (const poll of r.intervals.values()) poll();
    await r.tick(); assert.equal(r.calls.length, 4);
});

test('429 keeps the account and pending changes, respecting Retry-After before retry', async () => {
    let calls = 0;
    const r = runtime(async () => { if (++calls === 1) throw Object.assign(new Error('limited'), { status: 429, retryAfter: 30 }); });
    r.service.start(r.state, r.deps); await settle();
    r.channels[0].receive({ payload: { scope: 'tickets' } }); await r.tick();
    assert.equal(r.state.user.workspace_id, 'company-a');
    assert.equal(r.state.syncStatus, 'reconnecting');
    assert.ok([...r.timers.values()][0].delay >= 29000);
    await r.tick(); assert.equal(calls, 2);
});

test('stopping removes subscriptions, timers, listeners and invalidates in-flight context', async () => {
    let isCurrent;
    const r = runtime(async (_scopes, current) => { isCurrent = current; });
    r.service.start(r.state, r.deps); await settle();
    r.channels[0].receive({ payload: { scope: 'tickets' } }); await r.tick();
    assert.equal(isCurrent(), true);
    r.service.stop(r.state); await settle();
    assert.equal(isCurrent(), false);
    assert.equal(r.timers.size, 0); assert.equal(r.intervals.size, 0);
    assert.equal(r.doc.count(), 0); assert.equal(r.win.count(), 0);
    assert.equal(r.removed.length, 1);
    r.channels[0].receive({ payload: { scope: 'tickets' } });
    assert.equal(r.timers.size, 0);
});

test('external changes preserve typed fields and the original revision; a clean modal refreshes', () => {
    const r = runtime();
    r.state.modals = {};
    r.state.selectedTicket = { id: 'os-a', revision: 4, tech_notes: 'base', photos_urls: ['saved'] };
    r.service.captureTicket(r.state, r.state.selectedTicket);
    r.state.selectedTicket.tech_notes = 'minha digitação';
    r.state.selectedTicket.photos_urls.push('new-photo');
    const fresh = { id: 'os-a', revision: 5, tech_notes: 'outro PC', photos_urls: ['saved'] };
    const result = r.service.mergeRefreshedTicket(r.state, fresh);
    assert.equal(result.revision, 4);
    assert.equal(result.tech_notes, 'minha digitação');
    assert.deepEqual(result.photos_urls, ['saved', 'new-photo']);
    assert.equal(r.state.ticketModalExternalChange, true);
    r.service.captureTicket(r.state, fresh);
    r.state.selectedTicket = fresh;
    assert.equal(r.service.mergeRefreshedTicket(r.state, { ...fresh, revision: 6 }).revision, 6);
    assert.equal(r.state.ticketModalExternalChange, false);
});

test('an action form protects its snapshot even when its draft lives outside selectedTicket', () => {
    const r = runtime();
    r.state.modals = { outcome: true };
    r.state.selectedTicket = { id: 'os-a', revision: 4, tech_notes: 'base' };
    r.service.captureTicket(r.state, r.state.selectedTicket);
    const current = r.state.selectedTicket;
    assert.equal(r.service.mergeRefreshedTicket(r.state, { ...current, revision: 5 }), current);
    assert.equal(r.state.ticketModalExternalChange, true);
});

test('a committed save advances revision without losing unrelated or newly typed drafts', () => {
    const r = runtime(); r.state.modals = {};
    r.state.selectedTicket = { id: 'os-a', revision: 1, tech_notes: 'base', parts_needed: 'base parts' };
    r.service.captureTicket(r.state, r.state.selectedTicket);
    r.state.selectedTicket.tech_notes = 'typed after submit';
    r.state.selectedTicket.parts_needed = 'unsent parts';
    r.service.applyCommittedTicket(r.state, 'os-a', { id: 'os-a', revision: 2, tech_notes: 'submitted', parts_needed: 'base parts' }, { tech_notes: 'submitted' });
    assert.equal(r.state.selectedTicket.revision, 2);
    assert.equal(r.state.selectedTicket.tech_notes, 'typed after submit');
    assert.equal(r.state.selectedTicket.parts_needed, 'unsent parts');
    assert.equal(r.state.ticketModalSnapshot.tech_notes, 'submitted');
    assert.equal(r.state.ticketModalDirty, true);
});

test('transaction receipt advances only its confirmed fields and keeps the technical draft', () => {
    const r = runtime(); r.state.modals = {};
    r.state.selectedTicket = { id: 'os-a', revision: 4, tech_notes: 'base', parts_needed: 'A' };
    r.service.captureTicket(r.state, r.state.selectedTicket);
    r.state.selectedTicket.tech_notes = 'draft during request';
    const snapshot = { ...r.state.selectedTicket };
    const confirmed = r.service.applyCommandReceipt(r.state, snapshot, {
        ticket_id: 'os-a', ticket_revision: 6,
        ticket_updates: { parts_needed: 'C', parts_status: 'Pendente', tech_notes: 'must not be adopted' }
    });
    assert.equal(confirmed.revision, 6);
    assert.equal(r.state.selectedTicket.revision, 6);
    assert.equal(r.state.selectedTicket.tech_notes, 'draft during request');
    assert.equal(r.state.selectedTicket.parts_needed, 'C');
    assert.equal(r.state.ticketModalSnapshot.revision, 6);
    assert.equal(r.state.ticketModalSnapshot.tech_notes, 'base');
});

test('receipt preserves a draft when the command did not change that field from the base', () => {
    const r = runtime(); r.state.modals = {};
    r.state.selectedTicket = { id: 'os-a', revision: 4, parts_needed: 'A' };
    r.service.captureTicket(r.state, r.state.selectedTicket);
    r.state.selectedTicket.parts_needed = 'B';
    r.service.applyCommandReceipt(r.state, { id: 'os-a', revision: 4 }, {
        ticket_id: 'os-a', ticket_revision: 5, ticket_updates: { parts_needed: 'A' }
    });
    assert.equal(r.state.selectedTicket.parts_needed, 'B');
    assert.equal(r.state.selectedTicket.revision, 5);
    assert.equal(r.state.ticketModalSnapshot.parts_needed, 'A');
});

test('receipt that overlaps a changed draft requires review without adopting its new revision', () => {
    const r = runtime(); r.state.modals = {};
    r.state.selectedTicket = { id: 'os-a', revision: 4, parts_needed: 'A' };
    r.service.captureTicket(r.state, r.state.selectedTicket);
    r.state.selectedTicket.parts_needed = 'B';
    assert.throws(() => r.service.applyCommandReceipt(r.state, { id: 'os-a', revision: 4 }, {
        ticket_id: 'os-a', ticket_revision: 5, ticket_updates: { parts_needed: 'C' }
    }), error => error.code === 'AIDA_RECEIPT_DRAFT_CONFLICT' && error.unknownCommit === true);
    assert.equal(r.state.selectedTicket.parts_needed, 'B');
    assert.equal(r.state.selectedTicket.revision, 4);
    assert.equal(r.state.ticketModalSnapshot.revision, 4);
    assert.equal(r.state.ticketModalExternalChange, true);
});

test('missing, foreign and regressing receipts never silently rebase an editing snapshot', () => {
    const r = runtime(); r.state.modals = {};
    for (const receipt of [undefined, { ticket_id: 'other', ticket_revision: 6, ticket_updates: {} },
        { ticket_id: 'os-a', ticket_revision: 3, ticket_updates: {} }, { ticket_id: 'os-a', ticket_revision: 6 }]) {
        const ticket = { id: 'os-a', revision: 4 };
        assert.throws(() => r.service.applyCommandReceipt(r.state, ticket, receipt),
            error => error.code === 'AIDA_RECEIPT_MISSING' && error.unknownCommit === true);
        assert.equal(ticket.revision, 4);
    }
});
