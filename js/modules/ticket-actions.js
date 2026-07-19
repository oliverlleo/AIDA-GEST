// Arquivo de actions do Ticket
// Parte da infraestrutura de módulos

window.AIDATicketActions = {
    // ==========================================
    // SUBFASE 1 — FLUXO ADMINISTRATIVO BASE
    // ==========================================

    async createTicket(deps) {
        const startsWithApprovedBudget = Boolean(deps.state.ticketForm.budget_approved);
        const approvedRoute = deps.state.ticketForm.approved_route;
        const partsNeeded = String(deps.state.ticketForm.parts_needed || '').trim();
        const technicianIsRequired = !deps.state.ticketForm.is_outsourced && deps.isFieldRequired('responsible');
        const selectedTechnician = deps.state.ticketForm.technician_id;

        if (technicianIsRequired && (!selectedTechnician || selectedTechnician === 'all')) {
            deps.focusTicketField('technician');
            return deps.notify('Selecione o técnico responsável antes de criar o chamado.', 'error');
        }

        if (startsWithApprovedBudget && !['repair', 'purchase'].includes(approvedRoute)) {
            return deps.notify("Escolha se o chamado deve seguir para reparo ou compra de peças.", "error");
        }

        if (startsWithApprovedBudget && approvedRoute === 'purchase' && !deps.isPartsControlEnabled()) {
            return deps.notify("O controle de compra de peças está desativado. Envie o chamado direto para reparo.", "error");
        }

        if (startsWithApprovedBudget && deps.state.ticketForm.is_outsourced) {
            return deps.notify("O atalho de orçamento aprovado é exclusivo para o fluxo interno de reparo.", "error");
        }

        if (startsWithApprovedBudget && approvedRoute === 'purchase' && !partsNeeded) {
            deps.focusTicketField('parts_needed');
            return deps.notify("Informe as peças necessárias antes de enviar o chamado para compra.", "error");
        }

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
            if (techId === 'all' || !techId) techId = null;

            const isOsAuto = deps.isAutoOSGenerationEnabled();
            const initialStatus = startsWithApprovedBudget
                ? (approvedRoute === 'purchase' ? 'Compra Peca' : 'Andamento Reparo')
                : 'Aberto';

            const ticketData = {
                id: deps.state.ticketForm.id,
                workspace_id: deps.state.user.workspace_id,
                client_name: deps.state.ticketForm.client_name,
                os_number: isOsAuto ? null : deps.state.ticketForm.os_number, // Send null if auto
                device_model: deps.state.ticketForm.model,
                serial_number: deps.isFieldVisible('serial_number') ? deps.state.ticketForm.serial : null,
                defect_reported: deps.isFieldVisible('defect_reported') && deps.state.ticketForm.defects.length ? deps.state.ticketForm.defects.join(', ') : null,
                priority: deps.isFieldVisible('priority') ? deps.state.ticketForm.priority : 'Normal',
                contact_info: deps.isFieldVisible('contact_info') ? deps.state.ticketForm.contact : null,
                deadline: deps.isFieldVisible('deadline') ? (deps.toUTC(deps.state.ticketForm.deadline) || null) : null,
                analysis_deadline: (!startsWithApprovedBudget && deps.isFieldVisible('analysis_deadline')) ? (deps.toUTC(deps.state.ticketForm.analysis_deadline) || null) : null,
                device_condition: deps.isFieldVisible('device_condition') ? deps.state.ticketForm.device_condition : null,
                parts_needed: startsWithApprovedBudget && approvedRoute === 'purchase' ? partsNeeded : null,
                parts_status: startsWithApprovedBudget && approvedRoute === 'purchase' ? 'Pendente' : 'N/A',
                budget_status: startsWithApprovedBudget ? 'Aprovado' : 'Pendente',
                technician_id: (deps.state.ticketForm.is_outsourced || !deps.isFieldVisible('responsible')) ? null : techId,
                is_outsourced: deps.state.ticketForm.is_outsourced,
                outsourced_company_id: (deps.state.ticketForm.is_outsourced && deps.state.ticketForm.outsourced_company_id && deps.state.ticketForm.outsourced_company_id !== '') ? deps.state.ticketForm.outsourced_company_id : null,
                checklist_data: deps.isFieldVisible('checklist_entry') ? deps.state.ticketForm.checklist : [],
                checklist_final_data: deps.isFieldVisible('checklist_exit') ? deps.state.ticketForm.checklist_final : [],
                photos_urls: deps.isFieldVisible('photos') ? deps.state.ticketForm.photos : [],
                status: initialStatus,
                created_by_name: deps.state.user.name
            };

            // Configurable Validation
            const validation = deps.validateTicketRequirements(ticketData);
            if (!validation.valid) {
                deps.setLoading(false);
                deps.focusTicketFields(validation.missingFields || []);
                return deps.notify("Preencha os campos obrigatórios destacados.", "error");
            }

            const createdData = await deps.supabaseFetch('tickets', 'POST', ticketData);
            let createdTicket = createdData && createdData.length > 0 ? createdData[0] : ticketData;

            // Ensure we have the public_token (if backend generated it and frontend didn't get it back fully populated)
            if (!createdTicket.public_token) {
                const fresh = await deps.supabaseFetch(`tickets?id=eq.${createdTicket.id}&select=*`);
                if (fresh && fresh.length > 0) createdTicket = fresh[0];
            }

            const ctx = deps.getLogContext(createdTicket);
            const initialLog = startsWithApprovedBudget
                ? {
                    action: 'Novo Chamado - Orçamento Aprovado',
                    details: approvedRoute === 'purchase'
                        ? `Chamado criado com orçamento já aprovado para ${ctx.device} de ${ctx.client} e enviado para **Compra de Peças**: **${partsNeeded}**.`
                        : `Chamado criado com orçamento já aprovado para ${ctx.device} de ${ctx.client} e enviado direto para **Reparo**.`
                }
                : {
                    action: 'Novo Chamado',
                    details: `Um novo chamado foi criado para o ${ctx.device} de ${ctx.client}.`
                };
            await deps.logTicketAction(createdTicket.id, initialLog.action, initialLog.details);

            // Check and process appointments if present in state
            if (!startsWithApprovedBudget && deps.isAppointmentTypeEnabled('analysis') && deps.state.selectedAnalysisAppointment) {
                try {
                    const appt = deps.state.selectedAnalysisAppointment;
                    await deps.supabaseFetch('rpc/create_ticket_appointment', 'POST', {
                        p_ticket_id: createdTicket.id,
                        p_technician_id: deps.state.ticketForm.technician_id,
                        p_appointment_type: 'analysis',
                        p_scheduled_start: deps.toUTC(`${appt.date}T${appt.start}`),
                        p_scheduled_end: deps.toUTC(`${appt.date}T${appt.end}`),
                        p_notes: 'Agendamento de análise via painel'
                    });
                } catch (e) {
                    console.error("Erro ao salvar agendamento de análise:", e);
                    deps.notify("Chamado criado, mas falha ao salvar a agenda de análise.", "error");
                }
            }
            if (startsWithApprovedBudget && approvedRoute === 'repair' && deps.isAppointmentTypeEnabled('repair') && deps.state.selectedRepairAppointment) {
                try {
                    const appt = deps.state.selectedRepairAppointment;
                    await deps.supabaseFetch('rpc/create_ticket_appointment', 'POST', {
                        p_ticket_id: createdTicket.id,
                        p_technician_id: deps.state.ticketForm.technician_id,
                        p_appointment_type: 'repair',
                        p_scheduled_start: deps.toUTC(`${appt.date}T${appt.start}`),
                        p_scheduled_end: deps.toUTC(`${appt.date}T${appt.end}`),
                        p_notes: 'Agendamento de reparo via painel'
                    });
                } catch (e) {
                    console.error("Erro ao salvar agendamento de reparo:", e);
                    deps.notify("Chamado criado, mas falha ao salvar a agenda de reparo.", "error");
                }
            }

            window.AIDAStorageService?.clearLocalPhotoPreviews();
            deps.notify("Chamado criado!");
            deps.closeModal('ticket');
            await deps.fetchTickets(true); // forceListRefetch flag to true
        } catch (err) {
            deps.notify("Erro ao criar: " + err.message, "error");
        } finally {
            deps.setLoading(false);
        }
    },

    async finishAnalysis(ticketOrId, deps) {
        const ticket = deps.resolveTicket(ticketOrId);
        if (!ticket) return;

        if (deps.isPartsControlEnabled() && deps.state.analysisForm.needsParts && !deps.state.analysisForm.partsList) {
            return deps.notify("Liste as peças necessárias.", "error");
        }
        const ctx = deps.getLogContext(ticket);

        const techNotes = deps.state.selectedTicket && deps.state.selectedTicket.id === ticket.id
            ? deps.state.selectedTicket.tech_notes
            : ticket.tech_notes;

        await deps.updateStatus(ticket, 'Aprovacao', {
            parts_needed: deps.isPartsControlEnabled() ? deps.state.analysisForm.partsList : null,
            parts_status: deps.isPartsControlEnabled() && deps.state.analysisForm.partsList ? 'Pendente' : 'N/A',
            tech_notes: techNotes
        }, { action: 'Finalizou Análise', details: `${ctx.device} de ${ctx.client} enviado para fase de aprovação do cliente.` });

        await deps.supabaseFetch('rpc/complete_ticket_appointment', 'POST', { p_ticket_id: ticket.id, p_type: 'analysis' });
    },

    async approveRepair(ticketOrId, deps) {
        const ticket = deps.resolveTicket(ticketOrId);
        if (!ticket) return;

        const needsPartsPurchase = deps.isPartsControlEnabled() && Boolean(ticket.parts_needed);
        const hasRepairAppointment = Boolean(ticket.repair_scheduled || ticket.repair_scheduled_at);

        if (needsPartsPurchase) {
            const ctx = deps.getLogContext(ticket);
            return await deps.updateStatus(ticket, 'Compra Peca', { budget_status: 'Aprovado' }, {
                action: 'Aprovou Orçamento',
                details: `${ctx.client} aprovou o orçamento do ${ctx.device}.`
            });
        }

        // Sem compra de peças, o agendamento de reparo é concluído antes da
        // mudança de etapa. Cancelar o painel mantém a OS em Aprovação.
        if (deps.isAppointmentTypeEnabled('repair') && !hasRepairAppointment) {
            deps.state.openSchedulePanel('repair', ticket.technician_id, ticket, 'approveRepair');
            return false;
        }

        return await this.completeBudgetApproval(ticket, deps);
    },

    async completeBudgetApproval(ticketOrId, deps) {
        const ticket = deps.resolveTicket(ticketOrId);
        if (!ticket) return false;
        const ctx = deps.getLogContext(ticket);
        return await deps.updateStatus(ticket, 'Andamento Reparo', { budget_status: 'Aprovado' }, {
            action: 'Aprovou Orçamento',
            details: `${ctx.client} aprovou o orçamento do ${ctx.device}.`
        });
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

         // Quando a compra foi aberta no meio do reparo, o banco retoma um novo ciclo do cronômetro.
         if (ticket.repair_paused_at) {
             deps.setLoading(true);
             try {
                 await deps.supabaseFetch('rpc/resume_repair_after_parts', 'POST', { p_ticket_id: ticket.id });
                 deps.notify("Peças recebidas. Reparo retomado e cronômetro reiniciado.");
                 await deps.fetchTickets(true);
                 await deps.fetchGlobalLogs();
             } catch (e) {
                 deps.notify("Erro ao retomar reparo: " + e.message, "error");
             } finally {
                 deps.setLoading(false);
             }
             return;
         }

         const ctx = deps.getLogContext(ticket);
         const rawPart = ticket.parts_needed || 'peça';
         const part = `"${rawPart}"`;
         await deps.updateStatus(ticket, 'Andamento Reparo', {
             parts_status: 'Recebido',
             parts_received_at: new Date().toISOString()
         }, { action: 'Recebeu Peças', details: `Peça **${part}** recebida para o **${ctx.device}** de **${ctx.client}**. Reparo liberado.` });

         // Se não há agendamento de reparo ativo, sugere criar
         if (deps.isAppointmentTypeEnabled('repair') && !ticket.repair_scheduled) {
             deps.state.openSchedulePanel('repair', ticket.technician_id, ticket);
         }
    },

    async markDelivered(ticketOrId, deps) {
        const ticket = deps.resolveTicket(ticketOrId);
        if (!ticket) return;

        const ctx = deps.getLogContext(ticket);
        let action = 'Finalizou Entrega';
        let details = `**${ctx.device}** de **${ctx.client}** foi retirado.`;

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

        if (deps.isFieldVisible('deadline') && deps.isFieldVisible('analysis_deadline')
            && deps.state.editDeadlineForm.deadline && deps.state.editDeadlineForm.analysis_deadline) {
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
        if (deps.isFieldVisible('deadline') && oldDeadline !== newDeadline) {
            actionDetails.push(`de ${oldDeadline} para ${newDeadline} (Prazo)`);
        }
        if (deps.isFieldVisible('analysis_deadline') && oldAnalysis !== newAnalysis) {
            actionDetails.push(`de ${oldAnalysis} para ${newAnalysis} (Análise)`);
        }

        const actionLog = actionDetails.length > 0 ? {
            action: 'Alterou Prazo',
            details: `${deps.state.user.name} alterou prazos do ${ctx.device} de ${ctx.client}: ${actionDetails.join(', ')}`
        } : null;

        const updates = {};
        if (deps.isFieldVisible('deadline')) {
            updates.deadline = deps.toUTC(deps.state.editDeadlineForm.deadline) || null;
        }
        if (deps.isFieldVisible('analysis_deadline')) {
            updates.analysis_deadline = deps.toUTC(deps.state.editDeadlineForm.analysis_deadline) || null;
        }

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
        const { state, supabaseFetch, mutateTicket, fetchDeletedItems, fetchEmployees, notify, setLoading } = deps;

        if (!confirm("Deseja restaurar este item?")) return;

        if (type === 'ticket') {
            const ticketToRestore = state.deletedTickets.find(t => t.id === id) || { id };
            const actionLog = {
                action: 'Restaurou Chamado',
                details: `Chamado restaurado da lixeira por ${state.user.name}.`
            };

            await mutateTicket(ticketToRestore, 'restoreItem', {
                deleted_at: null
            }, actionLog, { showNotify: true, notifyMessage: "Item restaurado!", fetchTickets: true });

            await fetchDeletedItems();
            return;
        }

        setLoading(true);
        try {
            await supabaseFetch(`employees?id=eq.${id}`, 'PATCH', {
                deleted_at: null
            });
            notify("Item restaurado!");

            await fetchDeletedItems();
            await fetchEmployees();

        } catch(e) {
            notify("Erro ao restaurar: " + e.message, "error");
        } finally {
            setLoading(false);
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
        await deps.supabaseFetch('rpc/start_ticket_appointment', 'POST', { p_ticket_id: ticket.id, p_type: 'analysis' });
    },

    async startTicketAnalysis(ticket, deps) {
        deps.setLoading(true);
        try {
            // Call RPC
            await deps.supabaseFetch('rpc/start_ticket_analysis', 'POST', {
                p_ticket_id: ticket.id
            });
            await deps.supabaseFetch('rpc/start_ticket_appointment', 'POST', { p_ticket_id: ticket.id, p_type: 'analysis' });

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
        deps.setLoading(true);
        try {
            await deps.supabaseFetch('rpc/start_repair_timer', 'POST', { p_ticket_id: ticket.id });
            deps.notify("Reparo iniciado.");
            await deps.fetchTickets(true);
            await deps.fetchGlobalLogs();
        } catch (e) {
            deps.notify("Erro ao iniciar reparo: " + e.message, "error");
        } finally {
            deps.setLoading(false);
        }
    },

    async pauseRepairForParts(ticketOrId, deps) {
        const ticket = deps.resolveTicket(ticketOrId);
        const parts = String(deps.state.pauseRepairForPartsForm.parts || '').trim();
        if (!deps.isPartsControlEnabled()) return deps.notify("O controle de compra de peças está desativado.", "error");
        if (!ticket || !parts) return deps.notify("Informe a peça ou componente necessário.", "error");

        deps.setLoading(true);
        try {
            await deps.supabaseFetch('rpc/pause_repair_for_parts', 'POST', {
                p_ticket_id: ticket.id,
                p_parts_needed: parts
            });
            deps.closeModal('pauseRepairForParts');
            deps.notify("Reparo pausado e enviado para compra de peças.");
            await deps.fetchTickets(true);
            await deps.fetchGlobalLogs();
        } catch (e) {
            deps.notify("Erro ao pausar reparo: " + e.message, "error");
        } finally {
            deps.setLoading(false);
        }
    },

    async finishRepair(success, deps) {
        const ticket = deps.resolveTicket();
        if (!ticket) return;
        deps.setLoading(true);
        try {
            await deps.supabaseFetch('rpc/complete_repair_with_timer', 'POST', {
                p_ticket_id: ticket.id,
                p_success: success
            });
            deps.closeModal('outcome');
            deps.notify(success ? "Reparo finalizado com sucesso!" : "Reparo finalizado.");
            await deps.fetchTickets(true);
            await deps.fetchGlobalLogs();
        } catch (e) {
            deps.notify("Erro ao finalizar reparo: " + e.message, "error");
        } finally {
            deps.setLoading(false);
        }
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
            // Aciona fluxo visual de Agendamento do Novo Reparo (Cenario de Retrabalho)
            if (deps.isAppointmentTypeEnabled('repair') && !ticket.repair_scheduled) {
                deps.state.openSchedulePanel('repair', ticket.technician_id, ticket);
            }
        }
    },

    async requestPriority(ticketOrId, deps) {
        const ticket = deps.resolveTicket(ticketOrId);
        if (!ticket) return;
        if (!deps.isPriorityRequestEnabled()) return deps.notify("A solicitação de prioridade está desativada.", "error");
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
                outsourced_at: new Date().toISOString(),
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
        const safeClientName = ticket.client_name || '';
        const safeOsNumber = ticket.os_number || '';
        const safeDevice = ticket.device_model || '';

        // Custom context without duplication
        const cleanContext = {
            client: `${safeClientName} da OS ${safeOsNumber}`,
            device: `${safeDevice}`
        };

        const companyName = deps.getOutsourcedCompany(ticket.outsourced_company_id);

        await deps.updateStatus(ticket, deps.isFinalTestEnabled() ? 'Teste Final' : 'Retirada Cliente', {
            test_start_at: null // Reset test status to ensure "Start Test" appears
        }, {
            action: 'Recebeu de Terceiro',
            details: deps.isFinalTestEnabled()
                ? `O aparelho ${cleanContext.device} de ${cleanContext.client} foi recebido da parceira ${companyName} e enviado para testes.`
                : `O aparelho ${cleanContext.device} de ${cleanContext.client} foi recebido da parceira ${companyName} e liberado para retirada.`
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

        const actionLog = {
            action: 'Confirmou Compra',
            details: `Compra de **${itemsStr}** do fornecedor **${supplier.razao_social || 'Desconhecido'}** para o **${ctx.device}** de **${ctx.client}** foi realizada.`
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

         if (deps.getDeliveryMode() === 'simple') {
             return this.markDelivered(ticket, deps);
         }

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

        const shouldOpenWhatsApp = !deps.isWhatsAppDisabled();
        const contactDigits = String(ticket.contact_info || '').replace(/\D/g, '');
        const hasWhatsAppNumber = contactDigits.length >= 10;

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
            const link = deps.isModuleEnabled('public_tracker') ? deps.getTrackingLink(ticket) : null;
            const msg = link
                ? `Olá ${ticket.client_name}, seu orçamento está pronto. Acompanhe aqui: ${link}`
                : `Olá ${ticket.client_name}, seu orçamento está pronto.`;

            if (shouldOpenWhatsApp && hasWhatsAppNumber) {
                let number = contactDigits;
                if (number.length <= 11) number = '55' + number;
                window.open(`https://wa.me/${number}?text=${encodeURIComponent(msg)}`, '_blank');
                deps.notify("Orçamento marcado como Enviado (WhatsApp aberto).");
            } else if (shouldOpenWhatsApp) {
                deps.notify("Orçamento marcado como Enviado. O WhatsApp não foi aberto porque o cliente não possui telefone cadastrado.");
            } else {
                deps.notify("Orçamento marcado como Enviado.");
            }
        }
    }
};

