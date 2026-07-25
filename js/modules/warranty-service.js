// Warranty workflow helpers.
// All reads are bounded and the database derives the workspace from the actor.

(function () {
    function emptyAnalysisForm(ticket = {}) {
        return {
            needsParts: Boolean(ticket.parts_needed),
            partsList: ticket.parts_needed || '',
            warrantyCovered: '',
            warrantyDiagnosis: '',
            warrantyCause: '',
            warrantyEvidence: ''
        };
    }

    function mergeSummary(ticket, summaryMap) {
        if (!ticket?.id) return ticket;
        return summaryMap.get(ticket.id)
            ? { ...ticket, ...summaryMap.get(ticket.id) }
            : ticket;
    }

    window.AIDAWarrantyService = {
        emptyAnalysisForm,

        async fetchEligibleTickets(deps, customerId, search = '') {
            const { state, supabaseFetch } = deps;
            const lookup = state.warrantyLookup;
            const requestId = ++lookup.requestId;
            lookup.loading = true;
            try {
                const response = await supabaseFetch('rpc/get_warranty_eligible_tickets', 'POST', {
                    p_customer_id: customerId,
                    p_search: String(search || '').trim() || null,
                    p_limit: 30
                });
                if (requestId !== lookup.requestId || state.ticketForm.customer_id !== customerId) return [];
                lookup.items = Array.isArray(response?.items) ? response.items : [];
                return lookup.items;
            } finally {
                if (requestId === lookup.requestId) lookup.loading = false;
            }
        },

        async fetchEligibleForCustomer(deps, customerId, search = null) {
            if (!customerId) return [];
            const response = await deps.supabaseFetch('rpc/get_warranty_eligible_tickets', 'POST', {
                p_customer_id: customerId,
                p_search: String(search || '').trim() || null,
                p_limit: 50
            });
            return Array.isArray(response?.items) ? response.items : [];
        },

        async hydrateTickets(deps, tickets) {
            const items = Array.isArray(tickets) ? tickets : [];
            const ids = [...new Set(items.map(ticket => ticket?.id).filter(Boolean))];
            if (!ids.length) return items;

            const chunks = [];
            for (let index = 0; index < ids.length; index += 50) {
                chunks.push(ids.slice(index, index + 50));
            }
            const responses = await Promise.all(chunks.map(chunk =>
                deps.supabaseFetch('rpc/get_warranty_ticket_summaries', 'POST', {
                    p_ticket_ids: chunk
                })
            ));
            const summaries = responses.flatMap(response => Array.isArray(response) ? response : []);
            const summaryMap = new Map(
                (Array.isArray(summaries) ? summaries : []).map(summary => [summary.id, summary])
            );
            return items.map(ticket => mergeSummary(ticket, summaryMap));
        },

        buildTechnicalReport(form) {
            const covered = form.warrantyCovered === 'yes';
            const lines = [
                `DIAGNÓSTICO TÉCNICO: ${String(form.warrantyDiagnosis || '').trim()}`,
                `CAUSA IDENTIFICADA: ${String(form.warrantyCause || '').trim()}`,
                `${covered ? 'RELAÇÃO COM O SERVIÇO ORIGINAL' : 'EVIDÊNCIAS DE MAU USO OU CAUSA EXTERNA'}: ${String(form.warrantyEvidence || '').trim()}`,
                `DECISÃO: ${covered ? 'Defeito coberto pela garantia' : 'Defeito não coberto pela garantia'}`
            ];
            if (form.needsParts) {
                lines.push(`PEÇAS NECESSÁRIAS: ${String(form.partsList || '').trim()}`);
            }
            return lines.join('\n\n');
        },

        validateTechnicalDecision(form, partsEnabled) {
            if (!['yes', 'no'].includes(form.warrantyCovered)) {
                return 'Informe se o defeito é coberto pela garantia.';
            }
            if (String(form.warrantyDiagnosis || '').trim().length < 10) {
                return 'Descreva o diagnóstico técnico com pelo menos 10 caracteres.';
            }
            if (String(form.warrantyCause || '').trim().length < 5) {
                return 'Informe a causa identificada.';
            }
            if (String(form.warrantyEvidence || '').trim().length < 10) {
                return form.warrantyCovered === 'yes'
                    ? 'Explique a relação do defeito com o serviço original.'
                    : 'Registre as evidências de mau uso ou causa externa.';
            }
            if (partsEnabled && form.needsParts && String(form.partsList || '').trim().length < 2) {
                return 'Informe as peças necessárias.';
            }
            return null;
        },

        badge(ticket) {
            if (!ticket?.warranty_claim) return null;
            if (ticket.warranty_status === 'covered') {
                return { label: 'GARANTIA', className: 'bg-emerald-100 text-emerald-800 border-emerald-200', icon: 'fa-shield-check' };
            }
            if (ticket.warranty_status === 'not_covered') {
                return { label: 'NÃO COBERTO', className: 'bg-amber-100 text-amber-800 border-amber-200', icon: 'fa-shield-halved' };
            }
            return { label: 'GARANTIA EM ANÁLISE', className: 'bg-indigo-100 text-indigo-800 border-indigo-200', icon: 'fa-shield' };
        }
    };
})();
