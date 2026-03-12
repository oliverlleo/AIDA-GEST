// Arquivo de contexto do chamado (Ticket)
// Parte da infraestrutura de módulos

window.AIDATicketContext = {
    // These properties act as the single source of truth for the context
    state: {
        activeTicketId: null,
        activeModalContext: { name: null, ticketId: null }
    },

    // Resolves the most up-to-date ticket object
    resolveTicket(ticketOrId, ticketsArray, selectedTicketFallback) {
        const targetId = ticketOrId
            ? (typeof ticketOrId === 'object' ? ticketOrId.id : ticketOrId)
            : this.state.activeTicketId;

        if (!targetId) return null;

        // Always try to get fresh data from the main array
        const found = ticketsArray.find(t => t.id === targetId);

        // Fallbacks
        if (found) return found;
        if (typeof ticketOrId === 'object' && ticketOrId.id) return ticketOrId;
        return selectedTicketFallback;
    },

    // Safely sets the context when opening a modal
    setModalContext(ticketId, modalName) {
        this.state.activeTicketId = ticketId;
        this.state.activeModalContext = { name: modalName, ticketId: ticketId };
        return {
            activeTicketId: this.state.activeTicketId,
            activeModalContext: { ...this.state.activeModalContext }
        };
    },

    // Clears the context when closing modals
    clearContext() {
        this.state.activeTicketId = null;
        this.state.activeModalContext = { name: null, ticketId: null };
        return {
            activeTicketId: this.state.activeTicketId,
            activeModalContext: { ...this.state.activeModalContext }
        };
    }
};
