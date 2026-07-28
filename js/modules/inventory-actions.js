(function () {
    function normalizeRequestedItems(items = []) {
        return items
            .filter(item => item?.item_id && Number(item.quantity) > 0)
            .map(item => ({
                item_id: item.item_id,
                quantity: Number(item.quantity),
                notes: String(item.notes || '').trim() || null,
                original_item_id: item.original_item_id || null,
                substitution_type: item.substitution_type || null
            }));
    }

    window.AIDAInventoryActions = {
        async requestTicketParts(deps, ticketId, items, stage, allocateNow = false) {
            const normalized = normalizeRequestedItems(items);
            if (!ticketId) throw new Error('OS não identificada.');
            if (!normalized.length) throw new Error('Adicione ao menos uma peça.');

            return await deps.supabaseFetch('rpc/request_ticket_inventory_parts', 'POST', {
                p_ticket_id: ticketId,
                p_items: normalized,
                p_stage: stage,
                p_allocate_now: Boolean(allocateNow)
            });
        },

        async approveTicket(deps, ticketId) {
            if (!ticketId) throw new Error('OS não identificada.');
            return await deps.supabaseFetch('rpc/approve_ticket_with_inventory', 'POST', {
                p_ticket_id: ticketId
            });
        },

        routeMessage(result = {}) {
            if (result.route === 'repair') {
                return 'Todas as peças foram reservadas. O reparo pode continuar.';
            }
            if (result.route === 'purchase') {
                const missing = Number(result.missing_quantity || 0);
                return missing > 0
                    ? `Saldo disponível reservado. Falta comprar ${missing}.`
                    : 'A OS foi encaminhada para compra.';
            }
            if (result.route === 'schedule_repair') {
                return 'Peças reservadas. Faça o agendamento do reparo para continuar.';
            }
            return 'Peças registradas na OS.';
        }
    };
})();
