// Notes Service
// Responsável pelas operações no domínio de notas (internas e gerais)
// Parte da infraestrutura de módulos

window.AIDANotesService = {
    async fetchInternalNotes(ticketId, deps) {
        const { state, supabaseFetch } = deps;
        if (!state.user?.workspace_id) return;
        try {
            const data = await supabaseFetch(
                `internal_notes?select=*&workspace_id=eq.${state.user.workspace_id}&ticket_id=eq.${ticketId}&order=created_at.asc`
            );
            state.internalNotes = data || [];
        } catch (e) {
            console.error("Fetch Internal Notes Error:", e);
        }
    },

    async fetchGeneralNotes(deps) {
        const { state, supabaseFetch } = deps;
        if (!state.user?.workspace_id) return;
        try {
            let query = `internal_notes?select=*&workspace_id=eq.${state.user.workspace_id}&ticket_id=is.null&is_archived=eq.false`;

            if (!state.showResolvedNotes) {
                query += `&is_resolved=eq.false`;
            }

            if (state.noteDateFilter) {
                const start = new Date(state.noteDateFilter + 'T00:00:00').toISOString();
                const end = new Date(state.noteDateFilter + 'T23:59:59').toISOString();
                query += `&created_at=gte.${start}&created_at=lte.${end}`;
            }

            query += `&order=created_at.desc`;

            const data = await supabaseFetch(query);
            state.generalNotes = data || [];
        } catch (e) {
            console.error("Fetch General Notes Error:", e);
        }
    },

    async sendNote(ticketId = null, isGeneral = false, deps) {
        const { state, supabaseFetch, notify, setLoading, fetchGeneralNotes, fetchInternalNotes } = deps;

        const text = isGeneral ? state.newGeneralNoteText : state.newNoteText;
        const isChecklist = isGeneral ? state.generalNoteIsChecklist : state.noteIsChecklist;
        const checklistItems = isGeneral ? state.generalNoteChecklistItems : state.noteChecklistItems;

        if (!text.trim() && (!isChecklist || checklistItems.length === 0)) return;

        setLoading(true);
        try {
            const mentionRegex = /@(\w+)/g;
            const matches = text.match(mentionRegex) || [];
            const mentions = matches.map(m => m.substring(1));

            const cleanChecklist = checklistItems
                .filter(i => i.text.trim().length > 0)
                .map(i => ({ item: i.text, ok: i.ok }));

            const payload = {
                workspace_id: state.user.workspace_id,
                ticket_id: ticketId,
                author_id: state.user.id,
                author_name: state.user.name,
                content: text,
                checklist_data: isChecklist ? cleanChecklist : [],
                mentions: mentions,
                is_resolved: false,
                created_at: new Date().toISOString()
            };

            await supabaseFetch('internal_notes', 'POST', payload);

            if (isGeneral) {
                state.newGeneralNoteText = '';
                state.generalNoteIsChecklist = false;
                state.generalNoteChecklistItems = [];
                await fetchGeneralNotes();
            } else {
                state.newNoteText = '';
                state.noteIsChecklist = false;
                state.noteChecklistItems = [];
                if (ticketId) await fetchInternalNotes(ticketId);
            }
            state.showMentionList = false;

        } catch (e) {
            notify("Erro ao enviar nota: " + e.message, "error");
        } finally {
            setLoading(false);
        }
    },

    async toggleNoteCheckStatus(note, itemIndex, deps) {
        const { supabaseFetch } = deps;
        note.checklist_data[itemIndex].ok = !note.checklist_data[itemIndex].ok;

        try {
            await supabaseFetch(`internal_notes?id=eq.${note.id}`, 'PATCH', {
                checklist_data: note.checklist_data
            });
        } catch (e) {
            console.error("Error toggling checklist:", e);
            note.checklist_data[itemIndex].ok = !note.checklist_data[itemIndex].ok;
        }
    },

    async resolveNote(note, deps) {
        const { supabaseFetch, notify } = deps;
        const newStatus = !note.is_resolved;
        note.is_resolved = newStatus;

        try {
            await supabaseFetch(`internal_notes?id=eq.${note.id}`, 'PATCH', {
                is_resolved: newStatus
            });
        } catch (e) {
            note.is_resolved = !newStatus;
            notify("Erro ao atualizar status", "error");
        }
    },

    async archiveNote(note, deps) {
        const { state, supabaseFetch, notify } = deps;
        if (!confirm("Arquivar esta nota?")) return;
        try {
            await supabaseFetch(`internal_notes?id=eq.${note.id}`, 'PATCH', {
                is_archived: true,
                archived_at: new Date().toISOString()
            });
            if (note.ticket_id) {
                state.internalNotes = state.internalNotes.filter(n => n.id !== note.id);
            } else {
                state.generalNotes = state.generalNotes.filter(n => n.id !== note.id);
            }
        } catch (e) {
            notify("Erro ao arquivar", "error");
        }
    }
};
