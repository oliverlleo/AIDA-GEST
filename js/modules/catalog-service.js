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
    }
};
