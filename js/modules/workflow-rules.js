// Arquivo de regras de negócio de workflow
// Parte da infraestrutura de módulos

window.AIDAWorkflowRules = {
    canExecuteAction(ticket, action, hasRoleFn, trackerConfig) {
        if (!ticket) return false;

        const isOutsourced = ticket.is_outsourced;
        const status = ticket.status;

        // Check roles
        const isAdmin = hasRoleFn('admin');
        const isTech = hasRoleFn('tecnico');
        const isAttendant = hasRoleFn('atendente');
        const isTester = hasRoleFn('tester');

        // Use external helper if available, otherwise fallback
        const testFlowMode = window.AIDAConfigHelpers ?
                             window.AIDAConfigHelpers.getTestFlowMode(trackerConfig) :
                             (trackerConfig?.test_flow || 'kanban');

        switch (action) {
            case 'createTicket':
                return isAdmin || isAttendant || isTech;
            case 'startAnalysis':
                if (isOutsourced || status !== 'Aberto') return false;
                return isAdmin || isAttendant || isTech;
            case 'sendToOutsourced':
                if (!isOutsourced || status !== 'Aberto') return false;
                return isAdmin || isAttendant || isTech;
            case 'finishAnalysis':
                if (status !== 'Analise Tecnica' || !ticket.analysis_started_at) return false;
                return isAdmin || isTech;
            case 'sendBudget':
                if (status !== 'Aprovacao' || ticket.budget_status === 'Enviado') return false;
                return isAdmin || isAttendant;
            case 'approveRepair':
            case 'denyRepair':
                if (status !== 'Aprovacao' || ticket.budget_status !== 'Enviado') return false;
                return isAdmin || isAttendant;
            case 'markPurchased':
                if (status !== 'Compra Peca' || ticket.parts_status === 'Comprado') return false;
                return isAdmin || isAttendant;
            case 'confirmReceived':
                if (status !== 'Compra Peca' || ticket.parts_status !== 'Comprado') return false;
                return isAdmin || isAttendant;
            case 'startRepair':
                if (status !== 'Andamento Reparo' || ticket.repair_start_at) return false;
                return isAdmin || isTech;
            case 'finishRepair':
                if (status !== 'Andamento Reparo' || !ticket.repair_start_at) return false;
                return isAdmin || isTech;
            case 'startTest':
                if (status !== 'Teste Final' || ticket.test_start_at) return false;
                if (testFlowMode === 'tester') return isAdmin || isTester;
                return isAdmin || isTech;
            case 'concludeTest':
                if (status !== 'Teste Final' || !ticket.test_start_at) return false;
                if (testFlowMode === 'tester') return isAdmin || isTester;
                return isAdmin || isTech;
            case 'markAvailable':
            case 'confirmLogisticsOption': // Equivalent to make available but logistics flow
                if (status !== 'Retirada Cliente' || ticket.pickup_available) return false;
                return isAdmin || isAttendant || isTech;
            case 'markDelivered':
            case 'confirmCarrier': // Equivalent to final mile in logistics
                if (status !== 'Retirada Cliente' || !ticket.pickup_available) return false;
                return isAdmin || isAttendant;
            case 'receiveFromOutsourced':
            case 'cobrarOutsourced':
                if (status !== 'Terceirizado') return false;
                return isAdmin || isAttendant || isTech;
            case 'requestPriority':
                return !ticket.priority_requested;
            case 'deleteTicket':
            case 'restoreItem':
                return isAdmin;
            case 'saveTicketChanges':
            case 'saveDeadlines':
                return isAdmin || isTech || isAttendant;
            case 'submitPurchase':
                if (status !== 'Compra Peca' || ticket.parts_status === 'Comprado') return false;
                return isAdmin || isAttendant;
            case 'updateStatus':
                // Generic status update wrapper validation
                return isAdmin || isTech || isAttendant || isTester;
            default:
                return true;
        }
    }
};
