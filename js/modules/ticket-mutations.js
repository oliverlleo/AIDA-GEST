// Arquivo central de mutações
// Parte da infraestrutura de módulos

window.AIDATicketMutations = {
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

        deps.setLoading(true);
        try {
            // 2. Determine payload
            const finalUpdates = {
                ...updates,
                updated_at: new Date().toISOString()
            };

            // 3. Send to backend
            await deps.supabaseFetch(`tickets?id=eq.${ticket.id}`, 'PATCH', finalUpdates);

            // 4. Update selectedTicket directly to avoid flashing/stale data in UI
            deps.updateSelectedTicket(ticket.id, finalUpdates);

            // 5. Log Action
            if (actionLog) {
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
            console.error("Mutation Error:", error);
            deps.notify("Erro ao atualizar: " + (error.message || error), "error");
            return false;
        } finally {
            deps.setLoading(false);
        }
    },

    /**
     * Standardized wrapper for simply updating status and triggering a log.
     */
    async updateStatus(ticket, newStatus, additionalUpdates = {}, actionLog = null, deps) {
        const updates = { status: newStatus, ...additionalUpdates };
        return await this.mutateTicket(
            ticket,
            'updateStatus',
            updates,
            actionLog,
            { showNotify: true, notifyMessage: "Status atualizado", closeViewModal: true, fetchTickets: true },
            deps
        );
    }
};
