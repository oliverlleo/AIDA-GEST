// Catalog Service
// Responsável por ler e provisionar listas estáticas e catálogos operacionais
// Parte da infraestrutura de módulos

window.AIDACatalogService = {
    async fetchTemplates(deps) {
        if (!deps.state.user?.workspace_id) return;
        try {
            const data = await deps.supabaseFetch('checklist_templates?select=*');
            if (data) {
                deps.state.checklistTemplates = data;
                deps.state.checklistTemplatesEntry = data.filter(t => !t.type || t.type === 'entry');
                deps.state.checklistTemplatesFinal = data.filter(t => t.type === 'final');
            }
        } catch (e) {
            console.error("Fetch Templates Error:", e);
        }
    },

    async fetchDeviceModels(deps) {
        if (!deps.state.user?.workspace_id) return;
        try {
            const data = await deps.supabaseFetch(`device_models?select=*&workspace_id=eq.${deps.state.user.workspace_id}&order=name.asc`);
            if (data) deps.state.deviceModels = data;
        } catch(e) {
            console.error("Fetch Models Error:", e);
        }
    },

    async fetchDefectOptions(deps) {
        if (!deps.state.user?.workspace_id) return;
        try {
            const data = await deps.supabaseFetch(`defect_options?select=*&workspace_id=eq.${deps.state.user.workspace_id}&order=name.asc`);
            if (data) deps.state.defectOptions = data;
        } catch(e) {
            console.error("Fetch Defect Options Error:", e);
        }
    },

    async fetchOutsourcedCompanies(deps) {
        if (!deps.state.user?.workspace_id) return;
        try {
            const data = await deps.supabaseFetch(`outsourced_companies?select=*&workspace_id=eq.${deps.state.user.workspace_id}&order=name.asc`);
            if (data) deps.state.outsourcedCompanies = data;
        } catch(e) {
            console.error("Fetch Outsourced Companies Error:", e);
        }
    },

    async fetchFornecedores(deps) {
        if (!deps.state.user?.workspace_id) return;
        try {
            const data = await deps.supabaseFetch(`fornecedores?select=*&workspace_id=eq.${deps.state.user.workspace_id}&order=razao_social.asc`);
            if (data) deps.state.fornecedores = data;
        } catch (error) {
            console.error('Erro ao buscar fornecedores:', error);
            alert('Erro ao carregar fornecedores: ' + error.message);
        }
    },

    async saveFornecedor(deps) {
        const { state, supabaseFetch, notify, fetchFornecedores, setLoading, closeModal } = deps;
        setLoading(true);
        try {
            if (state.fornecedorForm.id) {
                await supabaseFetch(`fornecedores?id=eq.${state.fornecedorForm.id}`, 'PATCH', {
                    razao_social: state.fornecedorForm.razao_social,
                    cnpj: state.fornecedorForm.cnpj,
                    fornece: state.fornecedorForm.fornece,
                    whatsapp: state.fornecedorForm.whatsapp,
                    updated_at: new Date().toISOString()
                });
            } else {
                if (!state.user?.workspace_id) throw new Error("Workspace ID não encontrado.");
                await supabaseFetch('fornecedores', 'POST', {
                    workspace_id: state.user.workspace_id,
                    razao_social: state.fornecedorForm.razao_social,
                    cnpj: state.fornecedorForm.cnpj,
                    fornece: state.fornecedorForm.fornece,
                    whatsapp: state.fornecedorForm.whatsapp
                });
            }
            closeModal('fornecedor');
            await fetchFornecedores();
        } catch (error) {
            console.error('Erro ao salvar fornecedor:', error);
            alert('Erro ao salvar fornecedor: ' + error.message);
        } finally {
            setLoading(false);
        }
    },

    async deleteFornecedor(id, deps) {
        const { supabaseFetch, fetchFornecedores } = deps;
        if (!confirm('Tem certeza que deseja excluir este fornecedor?')) return;
        try {
            await supabaseFetch(`fornecedores?id=eq.${id}`, 'DELETE');
            await fetchFornecedores();
        } catch (error) {
            console.error('Erro ao excluir fornecedor:', error);
            alert('Erro ao excluir fornecedor: ' + error.message);
        }
    },

    async createOutsourcedCompany(name, phone, deps) {
        const { state, supabaseFetch, notify, fetchOutsourcedCompanies } = deps;
        if (!name || !name.trim()) return;
        if (!state.user?.workspace_id) return;

        try {
            await supabaseFetch('outsourced_companies', 'POST', {
                workspace_id: state.user.workspace_id,
                name: name.trim(),
                phone: phone ? phone.trim() : null
            });
            await fetchOutsourcedCompanies();
            notify("Empresa parceira cadastrada!", "success");
        } catch(e) {
            notify("Erro ao cadastrar: " + e.message, "error");
        }
    },

    async deleteOutsourcedCompany(id, deps) {
        const { supabaseFetch, notify, fetchOutsourcedCompanies } = deps;
        if (!confirm("Excluir esta empresa parceira?")) return;
        try {
            await supabaseFetch(`outsourced_companies?id=eq.${id}`, 'DELETE');
            notify("Empresa excluída.");
            await fetchOutsourcedCompanies();
        } catch(e) {
            notify("Erro ao excluir: " + e.message, "error");
        }
    },

    async createDeviceModel(name, deps) {
        const { state, supabaseFetch, notify, fetchDeviceModels } = deps;
        if (!name || !name.trim()) return false;
        if (!state.user?.workspace_id) return false;

        if (state.deviceModels.some(m => m.name.toLowerCase() === name.trim().toLowerCase())) {
            notify("Modelo já existe.", "error");
            return false;
        }

        try {
            await supabaseFetch('device_models', 'POST', {
                workspace_id: state.user.workspace_id,
                name: name.trim()
            });
            await fetchDeviceModels();
            notify("Modelo cadastrado!", "success");
            return true;
        } catch(e) {
            notify("Erro ao salvar modelo: " + e.message, "error");
            return false;
        }
    },

    async createDefectOption(name, deps) {
        const { state, supabaseFetch, notify, fetchDefectOptions } = deps;
        if (!name || !name.trim()) return false;
        if (!state.user?.workspace_id) return false;

        const trimmed = name.trim();
        if (state.defectOptions.some(option => option.name.toLowerCase() === trimmed.toLowerCase())) {
            notify("Defeito já cadastrado.", "error");
            return false;
        }

        try {
            await supabaseFetch('defect_options', 'POST', {
                workspace_id: state.user.workspace_id,
                name: trimmed
            });
            notify("Defeito cadastrado!", "success");
            await fetchDefectOptions();
            return true;
        } catch(e) {
            notify("Erro ao salvar defeito: " + e.message, "error");
            return false;
        }
    },

    async deleteDeviceModel(id, deps) {
        const { state, supabaseFetch, notify, fetchDeviceModels } = deps;
        if (!confirm("Excluir este modelo da lista?")) return;
        try {
            await supabaseFetch(`device_models?id=eq.${id}`, 'DELETE');
            notify("Modelo excluído.");
            await fetchDeviceModels();
            if (state.ticketForm.model && !state.deviceModels.find(m => m.name === state.ticketForm.model)) {
                state.ticketForm.model = '';
            }
        } catch(e) {
            notify("Erro ao excluir: " + e.message, "error");
        }
    },

    async deleteDefectOption(id, deps) {
        const { state, supabaseFetch, notify, fetchDefectOptions } = deps;
        if (!confirm("Excluir este defeito da lista?")) return;
        try {
            await supabaseFetch(`defect_options?id=eq.${id}`, 'DELETE');
            notify("Defeito excluído.");
            await fetchDefectOptions();
            const available = new Set(state.defectOptions.map(option => option.name));
            state.ticketForm.defects = (state.ticketForm.defects || []).filter(defect => available.has(defect));
        } catch(e) {
            notify("Erro ao excluir: " + e.message, "error");
        }
    },

    async saveTemplate(deps) {
        const { state, supabaseFetch, notify, fetchTemplates } = deps;
        if (!state.newTemplateName) return notify("Nomeie o modelo", "error");
        if (state.ticketForm.checklist.length === 0) return notify("Adicione itens", "error");

        try {
            await supabaseFetch('checklist_templates', 'POST', {
                workspace_id: state.user.workspace_id,
                name: state.newTemplateName,
                items: state.ticketForm.checklist.map(i => i.item),
                type: 'entry'
            });

            notify("Modelo salvo!");
            state.newTemplateName = '';
            fetchTemplates();
        } catch (error) {
            notify("Erro ao salvar: " + error.message, "error");
        }
    },

    async deleteTemplate(deps) {
        const { state, supabaseFetch, notify, fetchTemplates } = deps;
        if (!state.selectedTemplateId) return;
        if (!confirm("Tem certeza que deseja excluir este modelo?")) return;

        try {
            await supabaseFetch(`checklist_templates?id=eq.${state.selectedTemplateId}`, 'DELETE');

            notify("Modelo excluído.");
            state.selectedTemplateId = '';
            fetchTemplates();
        } catch (e) {
            notify("Erro ao excluir: " + e.message, "error");
        }
    },

    async saveTemplateFinal(deps) {
        const { state, supabaseFetch, notify, fetchTemplates } = deps;
        if (!state.newTemplateNameFinal) return notify("Nomeie o modelo final", "error");
        if (state.ticketForm.checklist_final.length === 0) return notify("Adicione itens", "error");

        try {
            await supabaseFetch('checklist_templates', 'POST', {
                workspace_id: state.user.workspace_id,
                name: state.newTemplateNameFinal,
                items: state.ticketForm.checklist_final.map(i => i.item),
                type: 'final'
            });

            notify("Modelo final salvo!");
            state.newTemplateNameFinal = '';
            fetchTemplates();
        } catch (error) {
            notify("Erro ao salvar: " + error.message, "error");
        }
    },

    async deleteTemplateFinal(deps) {
        const { state, supabaseFetch, notify, fetchTemplates } = deps;
        if (!state.selectedTemplateIdFinal) return;
        if (!confirm("Tem certeza que deseja excluir este modelo?")) return;
        try {
            await supabaseFetch(`checklist_templates?id=eq.${state.selectedTemplateIdFinal}`, 'DELETE');
            notify("Modelo excluído.");
            state.selectedTemplateIdFinal = '';
            fetchTemplates();
        } catch (e) {
            notify("Erro: " + e.message, "error");
        }
    }
};
