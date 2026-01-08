
// Logic for Service Orders Module

// --- CONSTANTS ---
const OS_STATUS = {
    NEW: 'new',
    ANALYZING: 'analyzing',
    APPROVAL: 'approval',
    BUYING_PARTS: 'buying_parts',
    REPAIRING: 'repairing',
    TESTING: 'testing',
    READY: 'ready',
    FINISHED: 'finished',
    CANCELED: 'canceled'
};

const OS_LABELS = {
    [OS_STATUS.NEW]: 'Triagem / Entrada',
    [OS_STATUS.ANALYZING]: 'Análise Técnica',
    [OS_STATUS.APPROVAL]: 'Aprovação Orçamento',
    [OS_STATUS.BUYING_PARTS]: 'Aguardando Peças',
    [OS_STATUS.REPAIRING]: 'Em Reparo',
    [OS_STATUS.TESTING]: 'Testes Finais',
    [OS_STATUS.READY]: 'Pronto p/ Retirada',
    [OS_STATUS.FINISHED]: 'Finalizado',
    [OS_STATUS.CANCELED]: 'Cancelado'
};

const OS_PRIORITY = {
    LOW: 'low',
    NORMAL: 'normal',
    HIGH: 'high',
    URGENT: 'urgent'
};

const OS_PRIORITY_LABELS = {
    [OS_PRIORITY.LOW]: 'Baixa',
    [OS_PRIORITY.NORMAL]: 'Normal',
    [OS_PRIORITY.HIGH]: 'Alta',
    [OS_PRIORITY.URGENT]: 'Urgente'
};

// --- MAIN EXTENSION ---

// We will extend the main Alpine component.
// Since the main component is in index.html inside a script, we can't easily "extend" it class-style.
// Instead, we will attach these methods to the `app()` object or create a mixin.
// For simplicity in this Setup, I will provide the functions to be copy-pasted into `js/main.js`
// OR I will refactor `js/main.js` to include this file.
// Let's modify `js/main.js` to dynamically load or just put the logic there.
// Actually, the cleanest way without a bundler is to merge this into `js/main.js` or attach to window.

window.osModule = function() {
    return {
        // Constants
        OS_STATUS,
        OS_LABELS,
        OS_PRIORITY,
        OS_PRIORITY_LABELS,

        // Data
        serviceOrders: [],
        osLogs: [], // Current logs for selected OS
        osSearchQuery: '',
        osFilterMode: 'all', // 'all' or 'tech' (controlled by tabs)

        // Forms & Modals
        showNewOsModal: false,
        showOsDetailsModal: false,
        selectedOs: null,

        newOsForm: {
            customer_name: '',
            customer_phone: '',
            device_model: '',
            serial_number: '',
            description: '',
            priority: 'normal',
            deadline: '',
            checklist: {}, // Object for checkboxes
            photos: [], // File objects
            template_id: ''
        },

        checklistTemplates: [],
        currentChecklistItems: ['Tela', 'Bateria', 'Carcaça', 'Botões', 'Conector Carga', 'Câmeras', 'Som'], // Default
        newChecklistItem: '',
        saveTemplateName: '',
        isSavingTemplate: false,

        // Actions
        technicalAnalysisForm: { notes: '', parts: '' },
        budgetForm: { value: 0 },
        repairResult: null, // 'success' or 'failure'
        failureReason: '',
        testResult: null, // 'approved' or 'problem'
        testNotes: '',

        // --- FETCHING ---

        async fetchServiceOrders() {
            if (!this.user?.workspace_id) return;

            this.loading = true;

            let query = supabaseClient
                .from('service_orders')
                .select('*')
                .eq('workspace_id', this.user.workspace_id);

            // Apply Search (Backend)
            if (this.osSearchQuery.length > 2) {
                // Using the generated column or simple OR ILIKE
                // Since Supabase JS .or() syntax is specific:
                const q = this.osSearchQuery;
                query = query.or(`customer_name.ilike.%${q}%,device_model.ilike.%${q}%,serial_number.ilike.%${q}%,id.eq.${q.replace(/[^0-9-]/g, '') || '00000000-0000-0000-0000-000000000000'}`);
            }

            // Sorting
            // Requirement: Priority (Alta > Baixa) then Deadline
            // We need to map priority enum to order. SQL doesn't sort enums easily without case.
            // We will sort in JS for complex logic or add a stored column for weight.
            // For now, let's fetch all (filtered) and sort in JS.

            const { data, error } = await query;

            if (error) {
                this.notify('Erro ao buscar ordens: ' + error.message, 'error');
            } else {
                this.serviceOrders = this.sortServiceOrders(data);
            }

            this.loading = false;
        },

        sortServiceOrders(orders) {
            const priorityWeight = { 'urgent': 4, 'high': 3, 'normal': 2, 'low': 1 };

            return orders.sort((a, b) => {
                // 1. Priority (Desc)
                const pA = priorityWeight[a.priority] || 0;
                const pB = priorityWeight[b.priority] || 0;
                if (pA !== pB) return pB - pA;

                // 2. Deadline (Asc) - Earliest first
                if (a.deadline && b.deadline) {
                    return new Date(a.deadline) - new Date(b.deadline);
                }
                if (a.deadline) return -1;
                if (b.deadline) return 1;

                return 0;
            });
        },

        get filteredColumns() {
            // Returns the columns to display based on View Mode
            const allColumns = [
                { id: 'new', title: 'Chamados / Triagem' },
                { id: 'analyzing', title: 'Análise Técnica' },
                { id: 'approval', title: 'Aprovação' },
                { id: 'buying_parts', title: 'Peças' },
                { id: 'repairing', title: 'Em Reparo' },
                { id: 'testing', title: 'Testes' },
                { id: 'ready', title: 'Pronto' },
                { id: 'finished', title: 'Finalizado' }
            ];

            if (this.osViewMode === 'tech') {
                return allColumns.filter(c => ['analyzing', 'repairing'].includes(c.id));
            }
            return allColumns;
        },

        getOrdersByStatus(status) {
            return this.serviceOrders.filter(o => o.status === status);
        },

        async fetchLogs(osId) {
            this.osLogs = []; // Reset
            const { data, error } = await supabaseClient
                .from('service_logs')
                .select('*')
                .eq('service_order_id', osId)
                .order('created_at', { ascending: false });

            if (data) {
                this.osLogs = data;
            }
        },

        async uploadAdditionalPhotos(files) {
            if (!this.selectedOs || !files || files.length === 0) return;

            this.loading = true;
            try {
                const newUrls = [];
                for (const file of files) {
                    const fileExt = file.name.split('.').pop();
                    const fileName = `${Date.now()}_${Math.random()}.${fileExt}`;
                    const filePath = `${this.user.workspace_id}/${fileName}`;

                    const { error: uploadError } = await supabaseClient.storage
                        .from('os-images')
                        .upload(filePath, file);

                    if (uploadError) throw uploadError;

                    const { data: { publicUrl } } = supabaseClient.storage
                        .from('os-images')
                        .getPublicUrl(filePath);

                    newUrls.push(publicUrl);
                }

                // Update DB
                const currentUrls = this.selectedOs.photos_url || [];
                const updatedUrls = [...currentUrls, ...newUrls];

                const { error } = await supabaseClient
                    .from('service_orders')
                    .update({ photos_url: updatedUrls })
                    .eq('id', this.selectedOs.id);

                if (error) throw error;

                // Update Local State
                this.selectedOs.photos_url = updatedUrls;
                await this.logAction(this.selectedOs.id, 'Adicionou novas fotos');
                this.notify('Fotos adicionadas com sucesso!', 'success');

            } catch (e) {
                console.error(e);
                this.notify('Erro ao enviar fotos: ' + e.message, 'error');
            } finally {
                this.loading = false;
            }
        },

        // --- CHECKLIST & TEMPLATES ---

        async loadChecklistTemplates() {
            const { data } = await supabaseClient
                .from('checklist_templates')
                .select('*')
                .eq('workspace_id', this.user.workspace_id);
            this.checklistTemplates = data || [];
        },

        applyTemplate() {
            if (!this.newOsForm.template_id) return;
            const t = this.checklistTemplates.find(x => x.id === this.newOsForm.template_id);
            if (t) {
                this.currentChecklistItems = t.items;
                // Reset checks
                this.newOsForm.checklist = {};
                t.items.forEach(i => this.newOsForm.checklist[i] = false);
            }
        },

        addChecklistItem() {
            if (this.newChecklistItem) {
                this.currentChecklistItems.push(this.newChecklistItem);
                this.newOsForm.checklist[this.newChecklistItem] = false;
                this.newChecklistItem = '';
            }
        },

        // --- CREATION ---

        async createServiceOrder() {
            this.loading = true;

            try {
                // 1. Upload Photos
                const photoUrls = [];
                if (this.newOsForm.photos.length > 0) {
                    for (const file of this.newOsForm.photos) {
                        const fileExt = file.name.split('.').pop();
                        const fileName = `${Date.now()}_${Math.random()}.${fileExt}`;
                        const filePath = `${this.user.workspace_id}/${fileName}`;

                        const { error: uploadError } = await supabaseClient.storage
                            .from('os-images')
                            .upload(filePath, file);

                        if (uploadError) throw uploadError;

                        const { data: { publicUrl } } = supabaseClient.storage
                            .from('os-images')
                            .getPublicUrl(filePath);

                        photoUrls.push(publicUrl);
                    }
                }

                // 2. Save Template if requested
                if (this.isSavingTemplate && this.saveTemplateName) {
                    await supabaseClient.from('checklist_templates').insert({
                        workspace_id: this.user.workspace_id,
                        name: this.saveTemplateName,
                        items: this.currentChecklistItems,
                        created_by: this.session?.user?.id // Only if admin, else null is fine or handle differently
                    });
                }

                // 3. Create Order
                const { error } = await supabaseClient.from('service_orders').insert({
                    workspace_id: this.user.workspace_id,
                    customer_name: this.newOsForm.customer_name,
                    customer_phone: this.newOsForm.customer_phone,
                    device_model: this.newOsForm.device_model,
                    serial_number: this.newOsForm.serial_number,
                    description: this.newOsForm.description,
                    priority: this.newOsForm.priority,
                    deadline: this.newOsForm.deadline || null,
                    checklist: this.newOsForm.checklist,
                    photos_url: photoUrls,
                    status: 'new',
                    created_by: this.session?.user?.id
                });

                if (error) throw error;

                // 4. Log
                // We need the ID of the created order to log properly, but for simplicity we assume success.
                // Or we fetch the latest.

                this.notify('Ordem de Serviço criada!', 'success');
                this.showNewOsModal = false;
                this.fetchServiceOrders();

            } catch (e) {
                console.error(e);
                this.notify('Erro ao criar OS: ' + e.message, 'error');
            } finally {
                this.loading = false;
            }
        },

        // --- ACTIONS & TRANSITIONS ---

        async updateOsStatus(id, newStatus, actionLabel, extraData = {}) {
            this.loading = true;

            const updatePayload = { status: newStatus, ...extraData };

            const { error } = await supabaseClient
                .from('service_orders')
                .update(updatePayload)
                .eq('id', id);

            if (error) {
                this.notify('Erro ao atualizar: ' + error.message, 'error');
            } else {
                // Log
                await this.logAction(id, actionLabel);
                this.notify(`Status alterado para: ${OS_LABELS[newStatus]}`, 'success');
                this.fetchServiceOrders();
                this.showOsDetailsModal = false; // Close modal usually
            }
            this.loading = false;
        },

        async logAction(osId, action, details = null) {
            await supabaseClient.from('service_logs').insert({
                service_order_id: osId,
                user_name: this.user.name,
                action: action,
                details: details ? JSON.stringify(details) : null
            });
        },

        // Specific Button Handlers

        async startTriage() {
            await this.updateOsStatus(this.selectedOs.id, 'analyzing', 'Iniciou Triagem');
        },

        async finishAnalysis() {
             await this.updateOsStatus(this.selectedOs.id, 'approval', 'Finalizou Análise', {
                 technical_notes: this.technicalAnalysisForm.notes,
                 required_parts: this.technicalAnalysisForm.parts
             });
        },

        async sendBudget() {
             await this.updateOsStatus(this.selectedOs.id, 'approval', 'Enviou Orçamento', {
                 budget_value: this.budgetForm.value,
                 budget_sent: true
             });
             // Refresh local state to unlock buttons
             this.selectedOs.budget_sent = true;
        },

        async approveBudget() {
            // Check if parts needed
            const hasParts = this.selectedOs.required_parts && this.selectedOs.required_parts.trim() !== '';
            const nextStatus = hasParts ? 'buying_parts' : 'repairing';
            await this.updateOsStatus(this.selectedOs.id, nextStatus, 'Aprovou Orçamento');
        },

        async denyBudget() {
            await this.updateOsStatus(this.selectedOs.id, 'ready', 'Negou Orçamento (Cancelado)');
        },

        async partsArrived() {
            await this.updateOsStatus(this.selectedOs.id, 'repairing', 'Peças Chegaram / Recebido');
        },

        async startRepair() {
             // Just Log, stay in repairing? Or distinct status?
             // Requirement: "Loga horário de início". Status is already Repairing.
             await this.logAction(this.selectedOs.id, 'Iniciou Execução do Reparo');
             this.notify('Início de reparo registrado.');
        },

        async finishRepair(success) {
            if (success) {
                await this.updateOsStatus(this.selectedOs.id, 'testing', 'Finalizou Reparo (Sucesso)', { repair_success: true });
            } else {
                await this.updateOsStatus(this.selectedOs.id, 'ready', 'Falha no Reparo', {
                    repair_success: false,
                    failure_notes: this.failureReason
                });
            }
        },

        async finishTest(approved) {
             if (approved) {
                 await this.updateOsStatus(this.selectedOs.id, 'ready', 'Aprovado no Teste Final');
             } else {
                 // Loop back to repair
                 // Need new deadline? Logic implies prompts.
                 await this.updateOsStatus(this.selectedOs.id, 'repairing', 'Reprovado no Teste', {
                     description: this.selectedOs.description + " [REWORK: " + this.testNotes + "]"
                 });
             }
        },

        async deliverDevice() {
             await this.updateOsStatus(this.selectedOs.id, 'finished', 'Entregue ao Cliente');
        }
    };
};
