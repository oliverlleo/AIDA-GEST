// Arquivo de actions do Ticket
// Parte da infraestrutura de módulos

window.AIDATicketActions = {
    // ==========================================
    // SUBFASE 1 — FLUXO ADMINISTRATIVO BASE
    // ==========================================

    async createTicket(deps) {
        // Basic Integrity Checks
        if (deps.state.deviceModels && deps.state.deviceModels.length > 0 && !deps.state.deviceModels.find(m => m.name === deps.state.ticketForm.model)) {
            return deps.notify("Modelo inválido. Cadastre-o no ícone + antes de salvar.", "error");
        }

        if (deps.state.ticketForm.deadline && deps.state.ticketForm.analysis_deadline) {
            const deadline = new Date(deps.state.ticketForm.deadline);
            const analysis = new Date(deps.state.ticketForm.analysis_deadline);
            if (analysis > deadline) {
                return deps.notify("O Prazo de Análise não pode ser maior que o Prazo de Entrega.", "error");
            }
        }

        deps.setLoading(true);

        try {
            let techId = deps.state.ticketForm.technician_id;
            if (techId === 'all') techId = null;

            const isOsAuto = deps.isAutoOSGenerationEnabled();

            const ticketData = {
                id: deps.state.ticketForm.id,
                workspace_id: deps.state.user.workspace_id,
                client_name: deps.state.ticketForm.client_name,
                os_number: isOsAuto ? null : deps.state.ticketForm.os_number, // Send null if auto
                device_model: deps.state.ticketForm.model,
                serial_number: deps.state.ticketForm.serial,
                defect_reported: deps.state.ticketForm.defects.length ? deps.state.ticketForm.defects.join(', ') : null,
                priority: deps.state.ticketForm.priority,
                contact_info: deps.state.ticketForm.contact,
                deadline: deps.toUTC(deps.state.ticketForm.deadline) || null,
                analysis_deadline: deps.toUTC(deps.state.ticketForm.analysis_deadline) || null,
                device_condition: deps.state.ticketForm.device_condition,
                technician_id: deps.state.ticketForm.is_outsourced ? null : techId,
                is_outsourced: deps.state.ticketForm.is_outsourced,
                outsourced_company_id: (deps.state.ticketForm.is_outsourced && deps.state.ticketForm.outsourced_company_id && deps.state.ticketForm.outsourced_company_id !== '') ? deps.state.ticketForm.outsourced_company_id : null,
                checklist_data: deps.state.ticketForm.checklist,
                checklist_final_data: deps.state.ticketForm.checklist_final,
                photos_urls: deps.state.ticketForm.photos,
                status: 'Aberto',
                created_by_name: deps.state.user.name
            };

            // Configurable Validation
            const validation = deps.validateTicketRequirements(ticketData);
            if (!validation.valid) {
                deps.setLoading(false);
                return deps.notify("Preencha os campos obrigatórios: " + validation.missing.join(', '), "error");
            }

            const createdData = await deps.supabaseFetch('tickets', 'POST', ticketData);
            let createdTicket = createdData && createdData.length > 0 ? createdData[0] : ticketData;

            // Ensure we have the public_token (if backend generated it and frontend didn't get it back fully populated)
            if (!createdTicket.public_token) {
                const fresh = await deps.supabaseFetch(`tickets?id=eq.${createdTicket.id}&select=*`);
                if (fresh && fresh.length > 0) createdTicket = fresh[0];
            }

            const ctx = deps.getLogContext(createdTicket);
            await deps.logTicketAction(createdTicket.id, 'Novo Chamado', `Um novo chamado foi criado para o ${ctx.device} de ${ctx.client}.`);

            deps.notify("Chamado criado!");
            deps.closeModal('ticket');
            await deps.fetchTickets();
        } catch (err) {
            deps.notify("Erro ao criar: " + err.message, "error");
        } finally {
            deps.setLoading(false);
        }
    },

    async finishAnalysis(ticketOrId, deps) {
        const ticket = deps.resolveTicket(ticketOrId);
        if (!ticket) return;

        if (deps.state.analysisForm.needsParts && !deps.state.analysisForm.partsList) {
            return deps.notify("Liste as peças necessárias.", "error");
        }
        const ctx = deps.getLogContext(ticket);

        const techNotes = deps.state.selectedTicket && deps.state.selectedTicket.id === ticket.id
            ? deps.state.selectedTicket.tech_notes
            : ticket.tech_notes;

        await deps.updateStatus(ticket, 'Aprovacao', {
            parts_needed: deps.state.analysisForm.partsList,
            tech_notes: techNotes
        }, { action: 'Finalizou Análise', details: `${ctx.device} de ${ctx.client} enviado para fase de aprovação do cliente.` });
    },

    async approveRepair(ticketOrId, deps) {
        const ticket = deps.resolveTicket(ticketOrId);
        if (!ticket) return;
        const nextStatus = ticket.parts_needed ? 'Compra Peca' : 'Andamento Reparo';
        const ctx = deps.getLogContext(ticket);
        await deps.updateStatus(ticket, nextStatus, { budget_status: 'Aprovado' }, { action: 'Aprovou Orçamento', details: `${ctx.client} aprovou o orçamento do ${ctx.device}.` });
    },

    async denyRepair(ticketOrId, deps) {
         const ticket = deps.resolveTicket(ticketOrId);
         if (!ticket) return;
         const ctx = deps.getLogContext(ticket);
         await deps.updateStatus(ticket, 'Retirada Cliente', { budget_status: 'Negado', repair_successful: false }, { action: 'Negou Orçamento', details: `${ctx.client} reprovou o orçamento do ${ctx.device}.` });
    },

    async confirmReceived(ticketOrId, deps) {
         const ticket = deps.resolveTicket(ticketOrId);
         if (!ticket) return;
         const ctx = deps.getLogContext(ticket);
         const rawPart = ticket.parts_needed || 'peça';
         const part = `<span class="text-brand-500 font-bold">${deps.escapeHtml(rawPart)}</span>`;
         await deps.updateStatus(ticket, 'Andamento Reparo', {
             parts_status: 'Recebido',
             parts_received_at: new Date().toISOString()
         }, { action: 'Recebeu Peças', details: `Peça ${part} recebida para o ${ctx.device} de ${ctx.client}. Reparo liberado.` });
    },

    async markDelivered(ticketOrId, deps) {
        const ticket = deps.resolveTicket(ticketOrId);
        if (!ticket) return;

        const ctx = deps.getLogContext(ticket);
        let action = 'Finalizou Entrega';
        let details = `${ctx.device} de ${ctx.client} foi retirado.`;

        if (ticket.delivery_method === 'carrier') {
            action = 'Entrega Confirmada';
            details = `${ctx.device} do ${ctx.client} chegou ao seu destino.`;
        }

        await deps.updateStatus(ticket, 'Finalizado', {
            delivered_at: new Date().toISOString()
        }, { action, details });
    },

    async saveDeadlines(deps) {
        const ticket = deps.resolveTicket();
        if (!ticket) return;

        if (deps.state.editDeadlineForm.deadline && deps.state.editDeadlineForm.analysis_deadline) {
            const deadline = new Date(deps.state.editDeadlineForm.deadline);
            const analysis = new Date(deps.state.editDeadlineForm.analysis_deadline);
            if (analysis > deadline) {
                return deps.notify("O Prazo de Análise não pode ser maior que o Prazo de Entrega.", "error");
            }
        }

        const oldDeadline = ticket.deadline ? new Date(ticket.deadline).toLocaleString() : 'Não definido';
        const newDeadline = deps.state.editDeadlineForm.deadline ? new Date(deps.state.editDeadlineForm.deadline).toLocaleString() : 'Não definido';

        const oldAnalysis = ticket.analysis_deadline ? new Date(ticket.analysis_deadline).toLocaleString() : 'Não definido';
        const newAnalysis = deps.state.editDeadlineForm.analysis_deadline ? new Date(deps.state.editDeadlineForm.analysis_deadline).toLocaleString() : 'Não definido';

        const ctx = deps.getLogContext(ticket);
        let actionDetails = [];
        if (oldDeadline !== newDeadline) {
            actionDetails.push(`de ${oldDeadline} para ${newDeadline} (Prazo)`);
        }
        if (oldAnalysis !== newAnalysis) {
            actionDetails.push(`de ${oldAnalysis} para ${newAnalysis} (Análise)`);
        }

        const actionLog = actionDetails.length > 0 ? {
            action: 'Alterou Prazo',
            details: `${deps.state.user.name} alterou prazos do ${ctx.device} de ${ctx.client}: ${actionDetails.join(', ')}`
        } : null;

        const updates = {
            deadline: deps.toUTC(deps.state.editDeadlineForm.deadline) || null,
            analysis_deadline: deps.toUTC(deps.state.editDeadlineForm.analysis_deadline) || null
        };

        const success = await deps.mutateTicket(ticket, 'saveDeadlines', updates, actionLog, { showNotify: true, notifyMessage: 'Prazos atualizados!', fetchTickets: true });

        if (success) {
            deps.setEditingDeadlines(false);
        }
    },

    async saveTicketChanges(deps) {
         const ticket = deps.resolveTicket();
         if (!ticket) return;
         await deps.mutateTicket(ticket, 'saveTicketChanges', {
             tech_notes: deps.state.selectedTicket.tech_notes,
             parts_needed: deps.state.selectedTicket.parts_needed,
             checklist_data: deps.state.selectedTicket.checklist_data,
             checklist_final_data: deps.state.selectedTicket.checklist_final_data,
             photos_urls: deps.state.selectedTicket.photos_urls
         }, null, { showNotify: true, notifyMessage: "Alterações salvas!", fetchTickets: true });
    },

    async deleteTicket(ticketOrId, deps) {
        const ticket = deps.resolveTicket(ticketOrId);
        if (!ticket) return;
        if (!confirm('Tem certeza que deseja excluir este chamado? Ele irá para a Lixeira e não aparecerá nas listagens.')) return;

        const actionLog = {
            action: 'Excluiu Chamado',
            details: `Chamado movido para a lixeira por ${deps.state.user.name}.`
        };

        await deps.mutateTicket(ticket, 'deleteTicket', {
            deleted_at: new Date().toISOString()
        }, actionLog, { showNotify: true, notifyMessage: 'Chamado movido para a Lixeira.', closeViewModal: true, fetchTickets: true });
    },

    async restoreItem(type, id, deps) {
        if (!confirm("Deseja restaurar este item?")) return;

        if (type === 'ticket') {
            const ticketToRestore = deps.state.deletedTickets.find(t => t.id === id) || { id };
            const actionLog = {
                action: 'Restaurou Chamado',
                details: `Chamado restaurado da lixeira por ${deps.state.user.name}.`
            };

            await deps.mutateTicket(ticketToRestore, 'restoreItem', {
                deleted_at: null
            }, actionLog, { showNotify: true, notifyMessage: "Item restaurado!", fetchTickets: true });

            await deps.fetchDeletedItems();
            return;
        }

        deps.setLoading(true);
        try {
            await deps.supabaseFetch(`employees?id=eq.${id}`, 'PATCH', {
                deleted_at: null
            });
            deps.notify("Item restaurado!");

            await deps.fetchDeletedItems();
            await deps.fetchEmployees();

        } catch(e) {
            deps.notify("Erro ao restaurar: " + e.message, "error");
        } finally {
            deps.setLoading(false);
        }
    },

    // ==========================================
    // SUBFASE 2 — FLUXO TÉCNICO
    // ==========================================

    async startAnalysis(ticket, deps) {
        const ctx = deps.getLogContext(ticket);
        await deps.updateStatus(ticket, 'Analise Tecnica', {}, {
            action: 'Iniciou Atendimento',
            details: `${ctx.device} de ${ctx.client} enviado para análise do técnico.`
        });
    },

    async startTicketAnalysis(ticket, deps) {
        deps.setLoading(true);
        try {
            // Call RPC
            await deps.supabaseFetch('rpc/start_ticket_analysis', 'POST', {
                p_ticket_id: ticket.id
            });

            // Update Local State
            if (deps.state.selectedTicket && deps.state.selectedTicket.id === ticket.id) {
                deps.state.selectedTicket.analysis_started_at = new Date().toISOString();
            }

            deps.notify("Análise iniciada com sucesso!");
            await deps.fetchTickets();
            if (deps.state.view === 'dashboard') deps.fetchGlobalLogs();

        } catch (e) {
            console.error("Start Analysis Error:", e);
            deps.notify("Erro ao iniciar: " + e.message, "error");
        } finally {
            deps.setLoading(false);
        }
    },

    async startRepair(ticketOrId, deps) {
        const ticket = deps.resolveTicket(ticketOrId);
        if (!ticket) return;
        const ctx = deps.getLogContext(ticket);
        const actionLog = {
            action: 'Iniciou Execução',
            details: `Reparo iniciado do ${ctx.device} de ${ctx.client}.`
        };
        const now = new Date().toISOString();
        await deps.mutateTicket(ticket, 'startRepair', { repair_start_at: now }, actionLog, { showNotify: false, fetchTickets: true });
    },

    async finishRepair(success, deps) {
        const ticket = deps.resolveTicket();
        if (!ticket) return;
        const nextStatus = success ? 'Teste Final' : 'Retirada Cliente';
        const updates = {
            repair_successful: success,
            repair_end_at: new Date().toISOString()
        };

        // Calculate Duration
        const ctx = deps.getLogContext(ticket);

        const detailMsg = success
            ? `O reparo do ${ctx.device} de ${ctx.client} foi finalizado com sucesso.`
            : `O ${ctx.device} de ${ctx.client} não teve reparo.`;

        deps.closeModal('outcome');
        await deps.updateStatus(ticket, nextStatus, updates, {
            action: 'Finalizou Reparo',
            details: detailMsg
        });
    },

    async startTest(ticketOrId, deps) {
        const ticket = deps.resolveTicket(ticketOrId);
        if (!ticket) return;
        const ctx = deps.getLogContext(ticket);
        const actionLog = {
            action: 'Iniciou Testes',
            details: `Os testes no ${ctx.device} de ${ctx.client} foram iniciados.`
        };
        const now = new Date().toISOString();
        await deps.mutateTicket(ticket, 'startTest', { test_start_at: now }, actionLog, { showNotify: false, fetchTickets: true });
    },

    async concludeTest(success, deps) {
        const ticket = deps.resolveTicket();
        if (!ticket) return;
        const ctx = deps.getLogContext(ticket);

        if (success) {
            deps.closeModal('outcome');
            // Redirect logic based on Logistics Mode
            // If standard mode, it goes to "Retirada Cliente" which matches current DB/UI logic.
            await deps.updateStatus(ticket, 'Retirada Cliente', {}, { action: 'Concluiu Testes', details: `O ${ctx.device} de ${ctx.client} foi aprovado.` });
        } else {
            // FAILURE LOGIC
            if (!deps.state.testFailureData.reason) return deps.notify("Descreva o defeito apresentado", "error");

            // Outsourced Flow Logic
            if (ticket.is_outsourced) {
                 if (!deps.state.testFailureData.action) return deps.notify("Selecione a ação (Devolver ou Reparo)", "error");

                 if (deps.state.testFailureData.action === 'return') {
                     if (!deps.state.testFailureData.newDeadline) return deps.notify("Defina um novo prazo", "error");

                     const count = (ticket.outsourced_return_count || 0) + 1;
                     const companyName = deps.getOutsourcedCompany(ticket.outsourced_company_id);

                     // Add note to history
                     const newNote = {
                         date: new Date().toISOString(),
                         text: deps.state.testFailureData.reason,
                         user: deps.state.user.name,
                         context: `Retorno ${count}x`
                     };
                     const updatedNotes = [...(ticket.outsourced_notes || []), newNote];

                     deps.closeModal('outcome');
                     await deps.updateStatus(ticket, 'Terceirizado', {
                         outsourced_deadline: deps.toUTC(deps.state.testFailureData.newDeadline),
                         outsourced_return_count: count,
                         test_start_at: null,
                         outsourced_notes: updatedNotes
                     }, {
                         action: 'Devolveu para Terceiro',
                         details: `${ctx.device} retornado para ${companyName} (${count}ª vez). Motivo: ${deps.state.testFailureData.reason}`
                     });
                     return;
                 }
            }

            if (!deps.state.testFailureData.newDeadline) return deps.notify("Defina um novo prazo", "error");

            const newNote = {
                date: new Date().toISOString(),
                text: deps.state.testFailureData.reason,
                user: deps.state.user.name,
                context: ticket.is_outsourced && deps.state.testFailureData.action === 'repair' ? 'Falha de Terceiro' : 'Reprova em Teste'
            };

            const existingNotes = Array.isArray(ticket.test_notes) ? ticket.test_notes : [];
            const updatedNotes = [...existingNotes, newNote];

            deps.closeModal('outcome');
            await deps.updateStatus(ticket, 'Andamento Reparo', {
                deadline: deps.toUTC(deps.state.testFailureData.newDeadline),
                priority: deps.state.testFailureData.newPriority,
                repair_start_at: null,
                test_start_at: null,
                status: 'Andamento Reparo',
                test_notes: updatedNotes
            }, { action: 'Reprovou Testes', details: 'Retornado para Reparo. Defeito: ' + deps.state.testFailureData.reason });
            deps.notify("Retornado para reparo com urgência!");
        }
    },

    async requestPriority(ticketOrId, deps) {
        const ticket = deps.resolveTicket(ticketOrId);
        if (!ticket) return;
        const ctx = deps.getLogContext(ticket);
        const actionLog = {
            action: 'Solicitou Prioridade',
            details: `Foi solicitado prioridade no ${ctx.device} de ${ctx.client}.`
        };

        await deps.mutateTicket(ticket, 'requestPriority', {
            priority_requested: true
        }, actionLog, { showNotify: true, notifyMessage: "Prioridade solicitada com sucesso!", fetchTickets: true });
    },

    // ==========================================
    // SUBFASE 3 — TERCEIRIZAÇÃO / COMPRA / LOGÍSTICA
    // ==========================================

    async sendToOutsourced(deps) {
        if (!deps.state.outsourcedForm.deadline) return deps.notify("Informe o prazo.", "error");
        if (!deps.state.outsourcedForm.company_id) return deps.notify("Selecione a empresa parceira.", "error");

        const ticket = deps.resolveTicket();
        if (!ticket) return;

        deps.setLoading(true);
        try {
            const companyId = deps.state.outsourcedForm.company_id;

            // Update ticket context with the selected company before generating log
            const tempTicketContext = { ...ticket, outsourced_company_id: companyId };
            const ctx = deps.getLogContext(tempTicketContext);
            const companyName = deps.getOutsourcedCompany(companyId);

            await deps.updateStatus(ticket, 'Terceirizado', {
                outsourced_deadline: deps.toUTC(deps.state.outsourcedForm.deadline),
                outsourced_company_id: companyId,
                is_outsourced: true,
                // If moving from Aberto, ensure analysis logic is skipped or marked as handled externally
                status: 'Terceirizado'
            }, {
                action: 'Enviou Terceirizado',
                details: `${ctx.device} de ${ctx.client} enviado para ${companyName}. Prazo: ${new Date(deps.state.outsourcedForm.deadline).toLocaleDateString('pt-BR')}.`
            });

            deps.closeModal('outsourced');
            deps.closeModal('viewTicket');
        } catch(e) {
            deps.notify("Erro: " + e.message, "error");
            deps.setLoading(false);
        }
    },

    async receiveFromOutsourced(ticketOrId, deps) {
        const ticket = deps.resolveTicket(ticketOrId);
        if (!ticket) return;

        // For this specific action, we don't want the (Terceirizado: X) suffix in the context
        // because the log message already says "recebido da X".
        const safeClientName = deps.escapeHtml(ticket.client_name);
        const safeOsNumber = deps.escapeHtml(ticket.os_number);
        const safeDevice = deps.escapeHtml(ticket.device_model);

        // Custom context without duplication
        const cleanContext = {
            client: `<b>${safeClientName} da OS ${safeOsNumber}</b>`,
            device: `<b>${safeDevice}</b>`
        };

        const companyName = deps.getOutsourcedCompany(ticket.outsourced_company_id);

        await deps.updateStatus(ticket, 'Teste Final', {
            test_start_at: null // Reset test status to ensure "Start Test" appears
        }, {
            action: 'Recebeu de Terceiro',
            details: `${cleanContext.device} de ${cleanContext.client} recebido da ${companyName}. Enviado para testes.`
        });
    },

    cobrarOutsourced(ticket, deps) {
        const phone = deps.getOutsourcedPhone(ticket.outsourced_company_id);
        if (!phone) return deps.notify("Telefone não cadastrado.", "error");

        // Context requested by user
        const msg = `Olá, gostaria de saber sobre o andamento do aparelho ${ticket.device_model} (OS ${ticket.os_number}) enviado para vocês.`;

        let number = phone.replace(/\D/g, '');
        // Ensure 55 prefix if not present (assuming BR number logic generally)
        if (!number.startsWith('55') && number.length >= 10) {
            number = '55' + number;
        }

        window.open(`https://wa.me/${number}?text=${encodeURIComponent(msg)}`, '_blank');
    },

    async submitPurchase(deps) {
        if (!deps.state.purchaseFlow.supplierId) {
            alert('Selecione um fornecedor.');
            return;
        }
        if (deps.state.purchaseFlow.items.length === 0 || deps.state.purchaseFlow.items.some(i => !i.name || i.quantity < 1)) {
            alert('Preencha os itens corretamente.');
            return;
        }

        const ticket = deps.state.tickets.find(t => t.id === deps.state.purchaseFlow.ticketId);
        const supplier = deps.state.fornecedores.find(f => f.id === deps.state.purchaseFlow.supplierId);
        const ctx = deps.getLogContext(ticket);

        const purchaseData = {
            supplier_id: supplier.id,
            supplier_name: supplier.razao_social,
            items: deps.state.purchaseFlow.items,
            purchased_at: new Date().toISOString(),
            purchased_by: deps.state.employeeSession ? deps.state.employeeSession.employee_id : null
        };

        const currentPurchases = Array.isArray(ticket.supplier_purchases) ? ticket.supplier_purchases : [];
        const updatedPurchases = [...currentPurchases, purchaseData];

        let itemsStr = deps.state.purchaseFlow.items.map(i => `${i.quantity}x ${i.name}`).join(', ');
        const itemsHtml = `<span class="text-brand-500 font-bold">${deps.escapeHtml(itemsStr)}</span>`;

        const actionLog = {
            action: 'Confirmou Compra',
            details: `Compra de ${itemsHtml} do fornecedor <b>${deps.escapeHtml(supplier.razao_social)}</b> para o ${ctx.device} de ${ctx.client} foi realizada.`
        };

        const updates = {
            parts_status: 'Comprado',
            parts_purchased_at: new Date().toISOString(),
            supplier_purchases: updatedPurchases
        };

        const success = await deps.mutateTicket(ticket, 'submitPurchase', updates, actionLog, { showNotify: false, fetchTickets: true });

        if (success) {
            deps.closeModal('supplierPurchase');

            // Open WhatsApp
            if (supplier.whatsapp) {
                let phone = supplier.whatsapp.replace(/\D/g, '');
                if (phone.length === 10 || phone.length === 11) {
                    phone = '55' + phone; // Add country code if not present
                }
                let msg = `Olá! Gostaria de solicitar a compra de: \n`;
                deps.state.purchaseFlow.items.forEach(i => {
                    msg += `- ${i.quantity}x ${i.name}\n`;
                });
                msg += `\nPara o aparelho: ${ticket.device_model}\nOS: ${ticket.os_number || ticket.id.slice(0, 8)}`;

                window.open(`https://wa.me/${phone}?text=${encodeURIComponent(msg)}`, '_blank');
            }
        }
    },

    async confirmLogisticsOption(type, deps) {
        if (type === 'pickup') {
            // Execute standard "Disponibilizar" logic for Client Pickup
            const ticket = deps.resolveTicket();
            if (!ticket) return;
            const ctx = deps.getLogContext(ticket);
            const actionLog = {
                action: 'Disponibilizou Retirada',
                details: `O ${ctx.device} de ${ctx.client} foi disponibilizado.`
            };

            const updates = {
                pickup_available: true,
                pickup_available_at: new Date().toISOString(),
                delivery_method: 'pickup'
            };

            const success = await deps.mutateTicket(ticket, 'confirmLogisticsOption', updates, actionLog, { showNotify: true, notifyMessage: "Disponibilizado para retirada.", closeViewModal: true, fetchTickets: true });
            if (success) {
                deps.closeModal('logistics');
                deps.sendTrackingWhatsApp();
            }
        }
    },

    async confirmCarrier(deps) {
        const form = deps.state.logisticsForm;
        // Validation: If tracking exists, carrier is mandatory.
        if (form.tracking && !form.carrier) {
            return deps.notify("Transportadora é obrigatória se houver código de rastreio.", "error");
        }
        if (deps.state.logisticsMode === 'carrier_form' && !form.carrier) {
             return deps.notify("Informe a transportadora.", "error");
        }

        const ticket = deps.resolveTicket();
        if (!ticket) return;
        const ctx = deps.getLogContext(ticket);
        const updates = {};
        let actionLog = null;

        if (deps.state.logisticsMode === 'add_tracking') {
            updates.tracking_code = form.tracking;
            actionLog = {
                action: 'Adicionou Rastreio',
                details: `Código de rastreio do cliente foi adicionado e o numero do rastrio ${form.tracking}`
            };
        } else {
            updates.delivery_method = 'carrier';
            updates.carrier_name = form.carrier;
            updates.tracking_code = form.tracking || null;
            updates.pickup_available = true;
            updates.pickup_available_at = new Date().toISOString();

            let logMsg = `Aparelho ${ctx.device} de ${ctx.client} foi enviado por transportadora.`;
            if (form.tracking) logMsg += ` Código de Rastreio ${form.tracking}.`;
            actionLog = {
                action: 'Enviou Transportadora',
                details: logMsg
            };
        }

        const success = await deps.mutateTicket(ticket, 'confirmCarrier', updates, actionLog, { showNotify: true, notifyMessage: "Informações de envio atualizadas!", closeViewModal: true, fetchTickets: true });

        if (success) {
            deps.closeModal('logistics');
            if (deps.state.logisticsMode !== 'add_tracking') {
                deps.sendCarrierWhatsApp(ticket, form.carrier, form.tracking);
            }
        }
    },

    async markAvailable(ticketOrId, deps) {
         const ticket = deps.resolveTicket(ticketOrId);
         if (!ticket) return;

         if (deps.isLogisticsEnabled()) {
             deps.openLogisticsModal(ticket);
             return;
         }

         // Legacy Flow
         const ctx = deps.getLogContext(ticket);
         const actionLog = {
             action: 'Disponibilizou Retirada',
             details: `O ${ctx.device} de ${ctx.client} foi disponibilizado.`
         };

         const success = await deps.mutateTicket(ticket, 'markAvailable', {
             pickup_available: true,
             pickup_available_at: new Date().toISOString()
         }, actionLog, { showNotify: false, fetchTickets: true });

         if (success) {
             deps.sendTrackingWhatsApp();
         }
    },

    async sendBudget(ticketOrId, deps) {
        const ticket = deps.resolveTicket(ticketOrId);
        if (!ticket) return;
        const ctx = deps.getLogContext(ticket);
        const actionLog = {
            action: 'Enviou Orçamento',
            details: `Orçamento para o ${ctx.device} de ${ctx.client} foi enviado para o cliente.`
        };

        const updates = {
            budget_status: 'Enviado',
            budget_sent_at: new Date().toISOString()
        };

        const success = await deps.mutateTicket(ticket, 'sendBudget', updates, actionLog, { showNotify: false, fetchTickets: true });

        if (success) {
            const link = deps.getTrackingLink(ticket);
            const msg = `Olá ${ticket.client_name}, seu orçamento está pronto. Acompanhe aqui: ${link}`;

            let number = ticket.contact_info.replace(/\D/g, '');
            if (number.length <= 11) number = '55' + number;

            if (!deps.isWhatsAppDisabled()) {
                window.open(`https://wa.me/${number}?text=${encodeURIComponent(msg)}`, '_blank');
                deps.notify("Orçamento marcado como Enviado (WhatsApp aberto).");
            } else {
                deps.notify("Orçamento marcado como Enviado.");
            }
        }
    }
};
