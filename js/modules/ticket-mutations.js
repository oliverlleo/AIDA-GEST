// Arquivo central de mutações
// Parte da infraestrutura de módulos

window.AIDATicketMutations = {
    pendingTickets: new Set(),

    getTicketVersion(ticket) {
        const revision = ticket?.revision;
        if (!ticket?.id || !/^[1-9]\d{0,17}$/.test(String(revision ?? ''))) return null;
        return { id: ticket.id, revision: String(revision) };
    },
    /**
     * Executes a state mutation on a ticket securely via Supabase.
     * @param {Object} ticket The ticket to mutate.
     * @param {string} actionName The action attempting the mutation (for validation).
     * @param {Object} updates Key-value pairs to update in the DB.
     * @param {Object|null} actionLog Optional log details {action: string, details: string}.
     * @param {Object} options Control flags like showNotify, fetchTickets.
     * @param {Object} deps Dependency injection from the framework (Alpine/main.js).
     * @returns {boolean} True if successful.
     */
    async mutateTicket(ticket, actionName, updates = {}, actionLog = null, options = {}, deps) {
        // Default options
        const opts = { showNotify: true, closeViewModal: false, fetchTickets: true, ...options };

        // 1. JS-Level enforcement
        if (!deps.canExecuteAction(ticket, actionName)) {
            console.warn(`[Workflow Engine] Mutation prevented. Action '${actionName}' is not allowed on ticket ${ticket.id} (${ticket.status})`);
            deps.notify("Ação não permitida para o estado atual.", "error");
            return false;
        }

        const ticketVersion = this.getTicketVersion(ticket);
        if (!ticketVersion) {
            deps.notify('Reabra esta OS para revisar a versão atual antes de salvar.', 'error');
            return false;
        }
        // UX guard only: the database comparison remains authoritative across PCs.
        if (this.pendingTickets.has(ticket.id)) return false;
        this.pendingTickets.add(ticket.id);

        deps.setLoading(true);
        let committed = false;
        try {
            // 2. Determine payload
            const finalUpdates = {
                ...updates,
                updated_at: new Date().toISOString()
            };

            // 3. Send to backend
            let result;
            if (opts.rpcEndpoint) {
                result = await deps.supabaseFetch(opts.rpcEndpoint, 'POST', opts.rpcPayload, { ticketVersion });
            } else {
                result = await deps.supabaseFetch(`tickets?id=eq.${ticket.id}`, 'PATCH', finalUpdates, { ticketVersion });
            }
            const savedRow = Array.isArray(result) ? result.find(row => row.id === ticket.id)
                : result?.id === ticket.id && result?.revision ? result : null;
            if (!opts.rpcEndpoint && !this.getTicketVersion(savedRow)) {
                throw Object.assign(new Error('A OS não está mais disponível para esta edição.'), { status: 409, code: 'PT409' });
            }
            committed = true;

            // 4. Update selectedTicket directly to avoid flashing/stale data in UI
            // Never guess a revision: RPCs may change the same OS several times.
            // A later refresh supplies the confirmed snapshot when an RPC returns a receipt.
            deps.updateSelectedTicket(ticket.id, savedRow || { ...finalUpdates, revision: null }, finalUpdates);

            // 5. Log Action
            if (actionLog && !opts.skipClientLog) {
                 await deps.logTicketAction(ticket.id, actionLog.action, actionLog.details);
            }

            // 6. UI Feedback
            if (opts.showNotify) {
                deps.notify(opts.notifyMessage || "Atualizado com sucesso!");
            }

            // 7. Refresh Lists if needed
            if (opts.fetchTickets) {
                 await deps.fetchTickets();
            }

            // 8. Modal management
            if (opts.closeViewModal) {
                deps.closeViewModal();
            }

            return true;
        } catch (error) {
            if (error?.contextChanged) return committed;
            console.error("Mutation Error:", error);
            if (committed) {
                deps.notify('A alteração foi salva. Não foi possível atualizar a tela ou o histórico agora; não é necessário repetir a gravação.', 'error');
                return true;
            }
            const isConflict = Number(error?.status) === 409 || error?.code === 'PT409';
            if (isConflict) {
                try { await deps.onConflict?.(ticket, error); }
                catch (refreshError) { console.error('Conflict refresh failed:', refreshError); }
            }
            deps.notify(isConflict
                ? 'Esta OS foi atualizada em outro acesso. Suas alterações continuam no formulário; revise a versão atual antes de salvar novamente.'
                : "Erro ao atualizar: " + (error.message || error), "error");
            return false;
        } finally {
            this.pendingTickets.delete(ticket.id);
            deps.setLoading(false);
        }
    },

    /**
     * Standardized wrapper for simply updating status and triggering a log.
     */
    async updateStatus(ticket, newStatus, additionalUpdates = {}, actionLog = null, deps) {
        const concludesTest = ticket?.status === 'Teste Final'
            && ['Retirada Cliente', 'Andamento Reparo', 'Terceirizado'].includes(newStatus);
        const options = { showNotify: true, notifyMessage: "Status atualizado", closeViewModal: true, fetchTickets: true };
        let updates = { status: newStatus, ...additionalUpdates };
        if (concludesTest) {
            // Leaving the tester's SELECT scope needs the server-authorized operation.
            // The server validates every field and derives the audit event itself.
            const { status: _status, updated_at: _updatedAt, ...testUpdates } = additionalUpdates;
            options.rpcEndpoint = 'rpc/conclude_ticket_test';
            options.rpcPayload = { p_ticket_id: ticket.id, p_status: newStatus, p_updates: testUpdates };
            options.skipClientLog = true;
            updates = { ...testUpdates, status: newStatus };
        }
        return await this.mutateTicket(
            ticket,
            concludesTest ? 'concludeTest' : 'updateStatus',
            updates,
            actionLog,
            options,
            deps
        );
    }
};
