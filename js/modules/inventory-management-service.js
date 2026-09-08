(function () {
    function number(value, fallback = 0) {
        const parsed = Number(String(value ?? '').replace(',', '.'));
        return Number.isFinite(parsed) ? parsed : fallback;
    }

    function request(deps, rpc, payload = {}) {
        return deps.supabaseFetch(`rpc/${rpc}`, 'POST', payload);
    }

    window.AIDAInventoryManagementService = {
        async loadWorkspaceData(deps) {
            const [locations, queue] = await Promise.all([
                request(deps, 'get_inventory_locations'),
                request(deps, 'get_inventory_purchase_queue')
            ]);
            return {
                groups: locations?.groups || [],
                locations: locations?.locations || [],
                schemes: locations?.schemes || [],
                pendingParts: queue?.pending_parts || [],
                purchases: queue?.purchases || []
            };
        },

        async loadItemDetail(deps, itemId) {
            return await request(deps, 'get_inventory_item_detail', {
                p_item_id: itemId
            });
        },

        async loadItemReservations(deps, itemId, cursor = null) {
            return await request(deps, 'get_inventory_item_reservations_page', {
                p_item_id: itemId,
                p_limit: 20,
                p_cursor: cursor || null
            });
        },

        async loadMovements(deps, itemId = null, cursor = null) {
            return await request(deps, 'get_inventory_movements_page', {
                p_item_id: itemId || null,
                p_limit: 30,
                p_cursor: cursor || null
            });
        },

        async saveLinks(deps, itemId, form) {
            return await request(deps, 'save_inventory_item_links', {
                p_item_id: itemId,
                p_model_ids: form.model_ids || [],
                p_suppliers: form.suppliers || [],
                p_relations: form.relations || []
            });
        },

        async transfer(deps, form) {
            if (!form.item_id || !form.from_location_id || !form.to_location_id) {
                throw new Error('Selecione o item, a origem e o destino.');
            }
            if (form.from_location_id === form.to_location_id) {
                throw new Error('A origem e o destino precisam ser diferentes.');
            }
            if (number(form.quantity, -1) <= 0) {
                throw new Error('Informe uma quantidade maior que zero.');
            }
            if (String(form.reason || '').trim().length < 5) {
                throw new Error('Explique o motivo da transferência.');
            }
            return await request(deps, 'transfer_inventory', {
                p_item_id: form.item_id,
                p_from_location_id: form.from_location_id,
                p_to_location_id: form.to_location_id,
                p_quantity: number(form.quantity),
                p_reason: String(form.reason).trim()
            });
        },

        async archiveItem(deps, itemId) {
            return await request(deps, 'archive_inventory_item', {
                p_item_id: itemId
            });
        },

        async createPurchase(deps, form) {
            const selectedItems = (form.items || [])
                .filter(item => item.selected && number(item.quantity) > 0);
            const supplierRegistryEnabled = form.supplier_registry_enabled !== false;
            const supplierName = String(form.supplier_name || '').trim();
            if (supplierRegistryEnabled && !form.supplier_id) throw new Error('Selecione o fornecedor.');
            if (!supplierRegistryEnabled && supplierName.length < 2) throw new Error('Informe o nome do fornecedor.');
            if (!selectedItems.length) throw new Error('Selecione ao menos uma peça pendente.');
            if (selectedItems.some(item => String(item.unit_cost ?? '').trim() === '' || number(item.unit_cost, -1) < 0)) {
                throw new Error('Informe o custo unitário de cada peça selecionada.');
            }
            const allocations = selectedItems.map(item => ({
                ticket_part_item_id: item.ticket_part_item_id,
                quantity: number(item.quantity),
                unit_cost: number(item.unit_cost)
            }));
            return await request(deps, 'create_inventory_purchase', {
                p_supplier_id: form.supplier_id,
                p_allocations: allocations,
                p_urgent: Boolean(form.urgent),
                p_notes: String(form.notes || '').trim() || null,
                p_supplier_name: supplierRegistryEnabled ? null : supplierName
            });
        },

        async loadTicketParts(deps, ticketId) {
            return await request(deps, 'get_ticket_inventory_parts', {
                p_ticket_id: ticketId
            });
        },

        async loadTicketBudgetCosts(deps, ticketId) {
            return await request(deps, 'get_ticket_inventory_budget_costs', {
                p_ticket_id: ticketId
            });
        },

        async returnTicketPart(deps, form) {
            if (!form.reservation_id || number(form.quantity, -1) <= 0) {
                throw new Error('Informe uma quantidade válida para devolução.');
            }
            if (String(form.reason || '').trim().length < 5) {
                throw new Error('Informe o motivo da devolução.');
            }
            return await request(deps, 'return_ticket_inventory', {
                p_reservation_id: form.reservation_id,
                p_quantity: number(form.quantity),
                p_reason: String(form.reason).trim()
            });
        },
        async loadPurchase(deps, purchaseId) {
            return await request(deps, 'get_inventory_purchase_detail', {
                p_purchase_id: purchaseId
            });
        },

        async receivePurchase(deps, purchaseId, rows, confirmAllocation) {
            const receipts = (rows || [])
                .filter(row => number(row.receive_quantity) > 0)
                .map(row => ({
                    purchase_item_id: row.purchase_item_id,
                    quantity: number(row.receive_quantity),
                    unit_cost: number(row.unit_cost, -1),
                    destination: row.destination === 'stock' ? 'stock' : 'direct_ticket',
                    location_id: row.destination === 'stock' ? (row.location_id || null) : null
                }));
            if (!receipts.length) throw new Error('Informe ao menos uma quantidade recebida.');
            if (receipts.some(row => row.unit_cost < 0)) {
                throw new Error('Informe o custo unitário dos itens recebidos.');
            }
            if (receipts.some(row => row.destination === 'stock' && !row.location_id)) {
                throw new Error('Escolha o endereço somente para as peças que serão guardadas no estoque.');
            }
            return await request(deps, 'receive_inventory_purchase', {
                p_purchase_id: purchaseId,
                p_receipts: receipts,
                p_confirm_allocation: Boolean(confirmAllocation)
            });
        },

        async allocatePurchase(deps, purchaseId) {
            return await request(deps, 'allocate_received_inventory_purchase', {
                p_purchase_id: purchaseId
            });
        },

        async cancelPurchase(deps, purchaseId, reason) {
            if (String(reason || '').trim().length < 5) {
                throw new Error('Informe o motivo do cancelamento.');
            }
            return await request(deps, 'cancel_inventory_purchase', {
                p_purchase_id: purchaseId,
                p_reason: String(reason).trim()
            });
        }
    };
})();
