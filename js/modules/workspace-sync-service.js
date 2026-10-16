// Realtime carries invalidations only. Every displayed record is fetched again
// through the authenticated API and its current authorization policies.
(function () {
    const controllers = new WeakMap();
    const SCOPES = ['tickets', 'inventory', 'notes', 'notifications', 'access', 'agenda'];
    const clone = value => value == null ? value : JSON.parse(JSON.stringify(value));
    const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
    const EDITABLE_FIELDS = ['tech_notes', 'parts_needed', 'checklist_data', 'checklist_final_data',
        'photos_urls', 'test_notes', 'outsourced_notes'];
    const EDIT_MODALS = ['outcome', 'logistics', 'outsourced', 'finishAnalysis', 'supplierPurchase',
        'pauseRepairForParts', 'rescheduleAppointment', 'inventoryPartRequest', 'inventoryTicketParts'];
    const COMMAND_FIELDS = ['status', 'technician_id', 'parts_needed', 'parts_status', 'budget_status',
        'analysis_scheduled', 'analysis_scheduled_at', 'repair_scheduled', 'repair_scheduled_at',
        'analysis_started_at', 'repair_start_at', 'repair_end_at', 'repair_paused_at', 'repair_resumed_at',
        'repair_pause_reason', 'repair_elapsed_seconds', 'repair_successful', 'updated_at'];

    function dirtyFields(state) {
        const base = state.ticketModalSnapshot;
        if (!base || base.id !== state.selectedTicket?.id) return [];
        return EDITABLE_FIELDS.filter(field => !same(base[field], state.selectedTicket[field]));
    }

    function hasDraft(state) {
        return Boolean(state.ticketModalDirty || state.editingDeadlines || state.schedulePanelOpen
            || EDIT_MODALS.some(name => state.modals?.[name]) || dirtyFields(state).length);
    }

    function captureTicket(state, ticket) {
        state.ticketModalSnapshot = clone(ticket);
        state.ticketModalDirty = false;
        state.ticketModalExternalChange = false;
        state.ticketModalUnavailable = false;
    }

    function mergeRefreshedTicket(state, fresh) {
        const current = state.selectedTicket;
        const base = state.ticketModalSnapshot;
        if (current?.id !== fresh?.id) return fresh;
        const changed = base?.id === fresh.id && base.revision != null && fresh.revision != null
            && String(base.revision) !== String(fresh.revision);
        if (hasDraft(state)) {
            // Keep the original revision along with the draft: saving it must
            // detect a conflict rather than silently adopting another writer's version.
            if (changed) state.ticketModalExternalChange = true;
            return current;
        }
        captureTicket(state, fresh);
        return fresh;
    }

    function applyCommittedTicket(state, id, committed, submitted = committed) {
        if (state.selectedTicket?.id !== id) return;
        const current = state.selectedTicket;
        const base = state.ticketModalSnapshot?.id === id ? state.ticketModalSnapshot : current;
        const preserved = {};
        for (const field of EDITABLE_FIELDS) {
            const wasEdited = !same(base[field], current[field]);
            const wasSubmitted = Object.prototype.hasOwnProperty.call(submitted, field);
            if (wasEdited && (!wasSubmitted || !same(current[field], submitted[field]))) {
                preserved[field] = clone(current[field]);
            }
        }
        state.selectedTicket = { ...current, ...committed, ...preserved };
        state.ticketModalSnapshot = clone({ ...base, ...committed });
        state.ticketModalDirty = Object.keys(preserved).length > 0;
        state.ticketModalExternalChange = false;
    }

    function applyCommandReceipt(state, ticket, receipt) {
        const expected = Number(ticket?.revision), revision = Number(receipt?.ticket_revision);
        const updates = receipt?.ticket_updates;
        if (!ticket?.id || receipt?.ticket_id !== ticket.id
            || !Number.isSafeInteger(expected) || expected < 1
            || !Number.isSafeInteger(revision) || revision < expected
            || !updates || typeof updates !== 'object' || Array.isArray(updates)) {
            throw Object.assign(new Error('A operação foi enviada, mas sua confirmação está incompleta. Consulte a OS antes de repetir ou continuar.'),
                { code: 'AIDA_RECEIPT_MISSING', unknownCommit: true });
        }
        const committed = { id: ticket.id, revision };
        for (const field of COMMAND_FIELDS) {
            if (Object.prototype.hasOwnProperty.call(updates, field)) committed[field] = clone(updates[field]);
        }
        if (state.selectedTicket?.id === ticket.id) {
            const overlappingDraft = dirtyFields(state).some(field =>
                Object.prototype.hasOwnProperty.call(committed, field)
                && !same(state.ticketModalSnapshot[field], committed[field])
                && !same(state.selectedTicket[field], committed[field]));
            if (overlappingDraft) {
                state.ticketModalExternalChange = true;
                throw Object.assign(new Error('A operação foi salva, mas alterou um campo que está em edição. Suas alterações foram mantidas; revise a OS antes de continuar.'),
                    { code: 'AIDA_RECEIPT_DRAFT_CONFLICT', status: 409, unknownCommit: true });
            }
            applyCommittedTicket(state, ticket.id, committed, {});
        }
        Object.assign(ticket, committed);
        return ticket;
    }

    function start(state, deps) {
        const workspace = state.user?.workspace_id;
        const identity = state.session?.user?.id;
        const previous = controllers.get(state);
        if (previous?.workspace === workspace && previous?.identity === identity) {
            previous.refreshAuth();
            return previous;
        }
        stop(state);
        if (!workspace || !identity || !deps.client?.channel) return null;
        const doc = deps.document || document;
        const win = deps.window || window;
        const schedule = deps.setTimeout || setTimeout;
        const cancel = deps.clearTimeout || clearTimeout;
        const repeat = deps.setInterval || setInterval;
        const cancelRepeat = deps.clearInterval || clearInterval;
        const pending = new Set();
        let timer = null, poll = null, stopped = false, inFlight = false, channel, subscribed = false;
        let retryAt = 0, lastStartedAt = 0, failures = 0;
        const listeners = [];
        const current = () => !stopped && state.user?.workspace_id === workspace
            && state.session?.user?.id === identity;
        const visible = () => doc.visibilityState !== 'hidden' && win.navigator?.onLine !== false;
        const listen = (target, event, callback) => {
            target.addEventListener(event, callback);
            listeners.push(() => target.removeEventListener(event, callback));
        };
        const enqueue = (scopes = SCOPES) => {
            if (!current()) return;
            for (const scope of scopes) if (SCOPES.includes(scope)) pending.add(scope);
            if (!timer && !inFlight && visible()) {
                const now = Date.now();
                timer = schedule(flush, Math.max(500, retryAt - now, lastStartedAt + 3000 - now));
            }
        };
        const flush = async () => {
            timer = null;
            if (!current() || !visible() || inFlight || !pending.size) return;
            if (deps.isReady && !deps.isReady()) { timer = schedule(flush, 1000); return; }
            const scopes = [...pending];
            pending.clear();
            inFlight = true;
            lastStartedAt = Date.now();
            try {
                await deps.refresh(scopes, current);
                if (current()) {
                    state.syncLastUpdatedAt = Date.now(); retryAt = 0; failures = 0;
                    state.syncStatus = subscribed ? 'live' : 'reconnecting';
                }
            } catch (error) {
                if (current() && error.name !== 'AbortError') {
                    for (const scope of scopes) pending.add(scope);
                    failures++;
                    const backoff = Math.min(60000, 5000 * (2 ** Math.min(failures - 1, 4)));
                    retryAt = Date.now() + Math.max(backoff, Number(error.retryAfter || 0) * 1000);
                    state.syncStatus = 'reconnecting';
                }
            } finally {
                inFlight = false;
                if (current() && pending.size && visible()) enqueue([]);
            }
        };
        const refreshAuth = async () => {
            try {
                if (current()) await deps.client.realtime?.setAuth(state.session.access_token);
                return current();
            } catch (_) { if (current()) state.syncStatus = 'reconnecting'; return false; }
        };
        const join = async () => {
            if (!await refreshAuth() || !current() || channel) return;
            channel = deps.client.channel(`workspace:${workspace}`, { config: { private: true } });
            channel.on('broadcast', { event: 'invalidate' }, message => {
                const scope = message?.payload?.scope;
                if (SCOPES.includes(scope)) enqueue([scope]);
            }).subscribe(status => {
                if (!current()) return;
                if (status === 'SUBSCRIBED') { subscribed = true; state.syncStatus = 'live'; enqueue(); }
                else if (['CHANNEL_ERROR', 'TIMED_OUT', 'CLOSED'].includes(status)) {
                    subscribed = false; state.syncStatus = 'reconnecting';
                }
            });
        };
        const controller = { workspace, identity, enqueue, refreshAuth: join, stop: () => {
            stopped = true;
            pending.clear();
            if (timer) cancel(timer);
            if (poll) cancelRepeat(poll);
            listeners.forEach(remove => remove());
            if (channel) Promise.resolve(deps.client.removeChannel(channel)).catch(() => {});
        } };
        controllers.set(state, controller);
        state.syncStatus = 'connecting';
        const wake = () => { if (visible()) { join(); enqueue(); } };
        listen(doc, 'visibilitychange', wake);
        listen(win, 'focus', wake);
        listen(win, 'online', wake);
        listen(win, 'pageshow', wake);
        listen(win, 'offline', () => { if (current()) state.syncStatus = 'offline'; });
        listen(win, 'pagehide', event => { if (!event.persisted) stop(state); });
        poll = repeat(() => { if (visible()) { if (!channel) join(); enqueue(); } }, 60000);
        // setAuth completes before joining, so private channel authorization
        // sees the current account JWT, never the project's public key.
        join();
        return controller;
    }

    function stop(state) {
        controllers.get(state)?.stop();
        controllers.delete(state);
        state.syncStatus = 'stopped';
    }

    window.AIDAWorkspaceSyncService = {
        SCOPES, start, stop, dirtyFields, hasDraft, captureTicket, mergeRefreshedTicket, applyCommittedTicket, applyCommandReceipt,
        invalidate(state, scopes) { controllers.get(state)?.enqueue(scopes); }
    };
})();
