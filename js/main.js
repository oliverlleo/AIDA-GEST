
// Configuração do Supabase
if (!window.SUPABASE_CONFIG) {
    console.error("CRITICAL: SUPABASE_CONFIG not found. Check js/supabase-config.js");
}

const SUPABASE_URL = window.SUPABASE_CONFIG?.URL || '';
const SUPABASE_KEY = window.SUPABASE_CONFIG?.KEY || '';

// Safe initialization
let supabaseClient;
if (SUPABASE_URL && SUPABASE_KEY) {
    try {
        supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY, {
            auth: {
                persistSession: true,
                autoRefreshToken: true,
                detectSessionInUrl: false
            }
        });
    } catch (e) {
        console.error("Supabase fail:", e);
    }
}

let isUnloading = false;
window.addEventListener('beforeunload', () => { isUnloading = true; });


// ==========================================
// GLOBAL UI HELPERS (XSS SAFE)
// ==========================================
window.formatLogDetails = function(text) {
    if (!text) return '';

    // 1. Convert plain text unsafe chars first to prevent arbitrary HTML injection
    let html = String(text).replace(/&/g, "&amp;")
                   .replace(/</g, "&lt;")
                   .replace(/>/g, "&gt;")
                   .replace(/"/g, "&quot;")
                   .replace(/'/g, "&#039;");

    // 2. Restore previously valid and safe tags (for old DB records)
    // Example: &lt;span class=&quot;text-brand-500 font-bold&quot;&gt;tela&lt;/span&gt;
    html = html.replace(/&lt;span class=&quot;([^&quot;]+)&quot;&gt;(.*?)&lt;\/span&gt;/gi, '<span class="$1">$2</span>');
    html = html.replace(/&lt;b&gt;(.*?)&lt;\/b&gt;/gi, '<b>$1</b>');

    // 3. Restore new markdown-style **bold** tags for future logs
    html = html.replace(/\*\*(.*?)\*\*/g, '<b>$1</b>');

    return html;
};


function app() {
    return {
        // State
        loading: false,
        error: null,
        session: null,
        employeeSession: null,
        user: null,
        workspaceName: '',
        companyCode: '',
        whatsappNumber: '',
        registrationSuccess: false,
        newCompanyCode: '',
        view: 'dashboard',
        authMode: 'employee',
        adminDashboardFilters: {
            dateStart: '',
            dateEnd: '',
            deviceModel: 'all',
            defect: 'all',
            technician: 'all',
            status: 'all',
            quickView: 'summary',
            viewMode: 'standard',
            defectSortField: 'total',
            defectSortDesc: true,
            viewType: 'data'
        },

        // Operational Filters (New Backend feature)
        // Home/Dashboard specific state
        homeOperationalFilters: {
            window: 'all',
            basis: 'auto',
            status: 'all',
            technician: 'all',
            search: ''
        },
        homeOperationalCounts: {
            today: 0,
            today_tomorrow: 0,
            next_7_days: 0,
            overdue: 0,
            no_deadline: 0,
            all: 0
        },
        homeStatusCounts: { open: 0, analysis: 0, approval: 0, pickup: 0 },
        homeOpsTotals: {
            pendingBudgets: 0, waitingBudgetResponse: 0, pendingPickups: 0,
            pendingTracking: 0, pendingDelivery: 0, pendingTech: 0,
            outsourcedToSend: 0, pendingOutsourced: 0, pendingPurchase: 0,
            pendingReceipt: 0, priorityTickets: 0, expiringDeliveries: 0,
            expiredDeliveries: 0, expiringAnalysis: 0, expiredAnalysis: 0
        },
        overviewQueueModal: {
            open: false, key: '', title: '', total: 0, items: [],
            loading: false, hasMore: false, nextCursor: null
        },
        homeOperationalItems: [],
        homeOperationalLoading: false,

        // Kanban/Chamados specific state
        kanbanOperationalFilters: {
            window: 'all',
            basis: 'auto',
            status: 'all',
            technician: 'all',
            search: ''
        },
        kanbanOperationalCounts: {
            today: 0,
            today_tomorrow: 0,
            next_7_days: 0,
            overdue: 0,
            no_deadline: 0,
            all: 0
        },
        kanbanOperationalLastResponse: null,

        // Tracker Configuration (NEW)
        trackerConfig: {
            logo_url: '',
            logo_size: 64, // Default size in px
            enable_logistics: false,
            disable_whatsapp_actions: false, // Disables automatic whatsapp opening and card icons
            enable_outsourced: false, // Outsourced Workflow Toggle
            test_flow: 'kanban', // 'kanban', 'technician', 'tester'
            custom_labels: {}, // Custom overrides for stage names
            colors: {
                background: '#FFF7ED', // orange-50
                card_bg: '#FFFFFF',
                header_bg: '#000000',
                text_primary: '#1a1a1a',
                text_secondary: '#6B7280', // gray-500
                progress_bar: '#FF6B00',
                progress_bg: '#E5E7EB', // gray-200
                icon_active: '#FF6B00',
                icon_inactive: '#D1D5DB', // gray-300
                status_label: '#FF6B00'
            },
            visible_stages: [
                'Aberto', 'Terceirizado', 'Analise Tecnica', 'Aprovacao', 'Compra Peca',
                'Andamento Reparo', 'Teste Final', 'Retirada Cliente', 'Finalizado'
            ],
            // New Requirement Features
            enable_required_ticket_fields: false,
            required_ticket_fields: {
                client_name: true,
                contact_info: false,
                os_number: true,
                priority: false,
                device_model: true,
                analysis_deadline: false,
                deadline: false,
                device_condition: false,
                responsible: true,
                defect_reported: true,
                checklist_entry: false,
                checklist_exit: false,
                photos: false,
                serial_number: false
            },
            ticket_field_modes: {
                client_name: 'required',
                contact_info: 'optional',
                os_number: 'required',
                serial_number: 'optional',
                priority: 'optional',
                device_model: 'required',
                analysis_deadline: 'required',
                deadline: 'required',
                device_condition: 'optional',
                responsible: 'required',
                defect_reported: 'required',
                checklist_entry: 'optional',
                checklist_exit: 'optional',
                photos: 'optional',
                analysis_schedule: 'optional',
                repair_schedule: 'optional'
            },
            workflow: {
                parts_control: true,
                final_test: true,
                analysis_timer: true,
                repair_timer: true,
                delivery_mode: 'complete',
                priority_requests: true
            },
            modules: {
                agenda: true,
                suppliers: true,
                manager_dashboard: true,
                public_tracker: true
            },
            overview_sections: {
                awaiting_start: true,
                awaiting_budget: true,
                parts_purchase: true,
                parts_receipt: true,
                tests: true,
                pickup: true,
                overdue: true,
                unscheduled: true,
                priority: true
            },
            // OS Number Generation
            os_generation: {
                enabled: false,
                mode: 'random', // 'random', 'sequential'
                prefix: '',
                start_seq: 1000,
                length: 6
            }
        },
        previewStatus: 'Andamento Reparo', // For Admin Preview

        // Data
        employees: [],
        outsourcedCompanies: [], // List of third-party vendors
        tickets: [],
        techTickets: [],
        deletedTickets: [],
        deletedEmployees: [],
        deviceModels: [],
        defectOptions: [],
        checklistTemplates: [],
        checklistTemplatesEntry: [],
        checklistTemplatesFinal: [],
        catalogManagement: {
            activeTab: 'models',
            search: '',
            modelName: '',
            editingModelId: null,
            editingModelName: '',
            defectName: '',
            editingDefectId: null,
            editingDefectName: '',
            checklistEditorOpen: false,
            checklistId: null,
            checklistName: '',
            checklistType: 'entry',
            checklistItems: [],
            checklistItemDraft: ''
        },
        notifications: [],

        // Pagination State
        ticketPagination: {
            page: 0,
            limit: 50,
            hasMore: true,
            isLoading: false,
            total: 0
        },
        searchDebounceTimer: null,
        realtimeDebounceTimer: null,

        // Fornecedores State
        fornecedores: [],
        fornecedorForm: { id: null, razao_social: '', cnpj: '', fornece: '', whatsapp: '' },

        // Supplier Purchase Flow State
        purchaseFlow: {
            ticketId: null,
            supplierId: '',
            items: [{ name: '', quantity: 1 }]
        },

        // Finalized Pagination State
        showFinalized: false,
        finalizedPage: 0,
        finalizedLimit: 50,
        finalizedHasMore: false,
        isLoadingFinalized: false,

        // Dashboard Data
        ops: {
            pendingBudgets: [],
            waitingBudgetResponse: [],
            pendingPickups: [],
            expiringAnalysis: [],
            expiredAnalysis: [],
            expiringDeliveries: [],
            expiredDeliveries: [],
            priorityTickets: [],
            pendingPurchase: [],
            pendingReceipt: [],
            pendingTech: [],
            // Logistics
            pendingTracking: [],
            pendingDelivery: [],
            // Outsourced
            outsourcedToSend: [], // New
            pendingOutsourced: []
        },
        homeOps: {
            pendingBudgets: [],
            waitingBudgetResponse: [],
            pendingPickups: [],
            expiringAnalysis: [],
            expiredAnalysis: [],
            expiringDeliveries: [],
            expiredDeliveries: [],
            priorityTickets: [],
            pendingPurchase: [],
            pendingReceipt: [],
            pendingTech: [],
            pendingTracking: [],
            pendingDelivery: [],
            outsourcedToSend: [],
            pendingOutsourced: []
        },
        metrics: {
             filteredTickets: [],
             techDeepDive: [],
             topModels: [],
             topDefects: [],
             topCombos: [],
             slowestModels: [],
             slowestDefects: [],
             slowestCombos: [],
             fastestTechs: [],
             slowestModelsSolution: [],
             slowestDefectsSolution: [],
             slowestCombosSolution: [],
             fastestTechsSolution: [],
             slowestModelsDelivery: [],
             slowestDefectsDelivery: [],
             slowestCombosDelivery: [],
             fastestTechsDelivery: [],
             techStats: [],
             successRate: 0,
             avgRepair: 0,
             avgSolution: 0,
             avgDelivery: 0,
             avgBudget: 0,
             avgPickupNotify: 0,
             analysisCount: 0,
             repairCount: 0,
             ticketsPerDay: 0,
             repairsToday: 0,
             repairsWeek: 0,
             repairsMonth: 0,
             ticketsToday: 0,
             ticketsWeek: 0,
             ticketsMonth: 0,
             logisticsStats: { pickup: {}, carrier: {} },
             outsourcedStats: {},
             internalStats: {}
        },

        // --- DASHBOARD OPTIMIZATION STATE ---
        dashboardMetricsPromise: null,
        lastDashboardParams: null,
        lastDashboardCallTime: 0,
        dashboardThrottleTimer: null,
        pendingRealtimeRefresh: false,
        loadedToken: null,
        initInFlight: false,

        // --- BOOTSTRAP STATE ---
        bootstrapInFlight: false,
        bootstrapDone: false,
        baseDataLoaded: false,
        realtimeReady: false,

        // --- IN-FLIGHT GUARDS ---
        globalLogsInFlight: false,
        notificationsInFlight: false,
        opsInFlight: false,

        // --- VIEW LOAD STATE ---
        viewsLoaded: {
            dashboard: false,
            admin_dashboard: false,
            kanban: false,
            tech_orders: false,
            tester_bench: false
        },

        // Daily Report State
        dailyReport: null,
        dailyReportLoading: false,
        dailyReportError: null,

        // Forms
        loginForm: { company_code: '', username: '', password: '' },
        adminForm: { email: '', password: '' },
        registerForm: { companyName: '', email: '', password: '' },
        employeeForm: { name: '', username: '', password: '', roles: [] },

        // Password Forms
        mustChangePassword: false,
        changePasswordForm: { oldPassword: '', newPassword: '', confirmPassword: '' },
        resetPasswordForm: { employeeId: '', newPassword: '', confirmPassword: '' },

        // Ticket Form
        ticketForm: {
            client_name: '', os_number: '', model: '', serial: '',
            defects: [], priority: 'Normal', contact: '',
            deadline: '', analysis_deadline: '', device_condition: '',
            technician_id: '',
            budget_approved: false, approved_route: 'repair', parts_needed: '',
            is_outsourced: false, outsourced_company_id: '', // New fields
            checklist: [], checklist_final: [], photos: [], notes: ''
        },
        ticketFormErrors: {},
        newChecklistItem: '',
        selectedTemplateId: '',
        newTemplateName: '',
        newChecklistFinalItem: '',
        selectedTemplateIdFinal: '',
        newTemplateNameFinal: '',

        // UI State for Actions
        selectedTicketAppointments: [],
        analysisForm: { needsParts: false, partsList: '' },
        pauseRepairForPartsForm: { ticketId: '', parts: '' },
        outcomeMode: '',
        showTestFailureForm: false,
        testFailureData: { newDeadline: '', newPriority: 'Normal', reason: '', action: '' }, // action: 'repair' or 'return'
        outsourcedForm: { company_id: '', deadline: '', price: '' }, // For sending to outsourced

        // Edit Deadlines State
        editingDeadlines: false,
        editDeadlineForm: { deadline: '', analysis_deadline: '' },

        // Selected Ticket & Modal Context
        activeTicketId: null,
        activeModalContext: { name: null, ticketId: null },
        selectedTicket: null, // Kept primarily for Alpine.js UI bindings
        ticketLogs: [],
        dashboardLogs: [],
        logViewMode: 'timeline',
        showShareModal: false,

        // Notes System State
        internalNotes: [],
        generalNotes: [],
        showNotesSidebar: false,
        newNoteText: '',
        newGeneralNoteText: '',
        noteIsChecklist: false,
        noteChecklistItems: [],
        generalNoteIsChecklist: false,
        generalNoteChecklistItems: [],

        // Notes Filters & UI
        showResolvedNotes: false,
        noteDateFilter: '',

        // Mention System
        showMentionList: false,
        mentionQuery: '',
        mentionTarget: '',
        mentionCursorPos: 0,
        mentionList: [],

        // Calendar State
        calendarView: 'week',
        currentCalendarDate: new Date(),
        showTodayOnly: false,
        benchCalendarMode: 'deadline', // 'deadline' or 'appointment' (shared by weekly and expanded views)

        // Kanban State
        kanbanScrollWidth: 0,
        columnFilters: {}, // { 'Aberto': { sort: 'default', search: '', dateStart: '', dateEnd: '' } }

        // Search
        searchQuery: '', // Global search
        activeQuickFilter: null,

        // Time
        currentTime: new Date(),

        // Modals
        // Scheduling Management View State
        scheduleManagement: {
            selectedTechnicianId: '',
            gridTechnicianId: '', // Added so clicking a card updates grid without affecting dropdown
            viewMode: 'week', // 'day' or 'week'
            referenceDate: new Date().toLocaleDateString('en-CA'),
            slotActionPopover: { open: false, date: '', slot: null, x: 0, y: 0 },
            typeFilter: 'all', // 'all', 'analysis', 'repair'
            loading: false,
            data: null,
            unscheduledLoading: false,
            unscheduledItems: [],
            unscheduledTotal: 0,
            withoutTechnicianItems: [],
            withoutTechnicianTotal: 0,
            conflictItems: [],
            conflictTotal: 0,
            lateWithoutScheduleItems: [],
            lateWithoutScheduleTotal: 0,
            capacitySummary: null,
            techConfig: {
                technician_id: '',
                workDays: [
                    { active: false, start: '09:00', end: '18:00' }, // Sunday
                    { active: true, start: '09:00', end: '18:00' }, // Monday
                    { active: true, start: '09:00', end: '18:00' }, // Tuesday
                    { active: true, start: '09:00', end: '18:00' }, // Wednesday
                    { active: true, start: '09:00', end: '18:00' }, // Thursday
                    { active: true, start: '09:00', end: '18:00' }, // Friday
                    { active: false, start: '09:00', end: '12:00' }  // Saturday
                ],
                hasBreak: true,
                breakStart: '12:00',
                breakEnd: '13:00',
                slotDuration: 30,
                maxConcurrent: 1
            },
            editingAppointment: {
                ticket_id: '',
                type: 'analysis',
                original: null,
                ticketContext: null,
                new_date: '',
                new_start: '',
                new_end: '',
                new_technician_id: '',
                notes: ''
            },
            editingBlock: {
                block_id: null,
                date: '',
                start: '',
                end: '',
                notes: ''
            },
        },

        // Scheduling State
        schedulePanelOpen: false,
        schedulePanelMode: '', // 'analysis' or 'repair'
        scheduleAvailabilityLoading: false,
        scheduleAvailabilityData: null,
        selectedAnalysisAppointment: null,
        selectedRepairAppointment: null,
        scheduleCurrentWeekStart: null,

        modals: { newEmployee: false, editEmployee: false, ticket: false, viewTicket: false, outcome: false, logs: false, calendar: false, notifications: false, recycleBin: false, logistics: false, outsourced: false, forceChangePassword: false, resetPassword: false, finishAnalysis: false, fornecedor: false, supplierPurchase: false, pauseRepairForParts: false, rescheduleAppointment: false, scheduleBlock: false, techScheduleSettings: false, confirmCreateTicket: false, confirmScheduleRepair: false },
        bypassAnalysisCheck: false,
        bypassRepairCheck: false,

        // Logistics State
        logisticsMode: 'initial', // 'initial', 'carrier_form', 'add_tracking'
        logisticsForm: { carrier: '', tracking: '' },

        // Notifications
        notificationsList: [],
        showReadNotifications: false,

        // Constants
        PRIORITIES: ['Baixa', 'Normal', 'Alta', 'Urgente'],
        STATUS_COLUMNS: [
            'Aberto', 'Terceirizado', 'Analise Tecnica', 'Aprovacao', 'Compra Peca',
            'Andamento Reparo', 'Teste Final', 'Retirada Cliente', 'Finalizado'
        ],
        STATUS_LABELS: {
            'Aberto': 'Aberto',
            'Terceirizado': 'Terceirizado',
            '…47268 tokens truncated…hase: 'Aguardando Compra',
                pendingReceipt: 'Aguardando Recebimento',
                priorityTickets: 'Prioridade',
                expiringDeliveries: 'Entrega Expirando',
                expiredDeliveries: 'Entrega Expirada',
                expiringAnalysis: 'Análise Expirando',
                expiredAnalysis: 'Análise Expirada'
            };
            return titles[key] || 'Chamados';
        },

        syncHomeOverviewQueues(queues = {}) {
            Object.keys(this.homeOpsTotals).forEach(key => {
                const queue = queues?.[key] || {};
                this.homeOps[key] = Array.isArray(queue.items) ? queue.items : [];
                this.homeOpsTotals[key] = Number(queue.total || 0);
            });
            this.homeOperationalItems = [];
        },

        async openOverviewQueueModal(key) {
            this.overviewQueueModal = {
                open: true,
                key,
                title: this.getOverviewQueueTitle(key),
                total: this.getHomeOpsTotal(key),
                items: Array.isArray(this.homeOps?.[key]) ? [...this.homeOps[key]] : [],
                loading: false,
                hasMore: true,
                nextCursor: null
            };
            await this.loadOverviewQueuePage(true);
        },

        closeOverviewQueueModal() {
            this.overviewQueueModal.open = false;
        },

        async loadOverviewQueuePage(reset = false) {
            const modal = this.overviewQueueModal;
            if (!modal.open || modal.loading) return;
            if (!reset && !modal.hasMore) return;

            modal.loading = true;
            if (reset) {
                modal.items = [];
                modal.nextCursor = null;
            }

            try {
                const f = this.homeOperationalFilters;
                const search = String(f.search || '').trim();
                const response = await this.supabaseFetch('rpc/get_overview_queue_page', 'POST', {
                    p_queue_key: modal.key,
                    p_window: f.window,
                    p_basis: this.getEffectiveOperationalBasis(f.basis),
                    p_status: f.status !== 'all' ? f.status : null,
                    p_technician_id: f.technician !== 'all' ? f.technician : null,
                    p_search: search || null,
                    p_limit: 20,
                    p_cursor: reset ? null : modal.nextCursor
                });

                if (!response) return;
                const incoming = Array.isArray(response.items) ? response.items : [];

                if (reset) {
                    modal.items = incoming;
                } else {
                    const existingIds = new Set(modal.items.map(ticket => ticket.id));
                    modal.items.push(...incoming.filter(ticket => !existingIds.has(ticket.id)));
                }

                modal.total = Number(response.total || 0);
                modal.hasMore = Boolean(response.has_more);
                modal.nextCursor = response.next_cursor || null;
            } catch (error) {
                console.error('Failed to load Overview queue page', error);
                this.notify('Erro ao carregar mais chamados.', 'error');
            } finally {
                modal.loading = false;
            }
        },

        openTicketFromOverviewQueue(ticket) {
            this.closeOverviewQueueModal();
            this.viewTicketDetails(ticket);
        },

        async fetchHomeOperationalQueue() {
            if (!this.user?.workspace_id) return;
            try {
                this.homeOperationalLoading = true;
                const f = this.homeOperationalFilters;
                const search = String(f.search || '').trim();
                const response = await this.supabaseFetch('rpc/get_operational_queue', 'POST', {
                    p_window: f.window,
                    p_basis: this.getEffectiveOperationalBasis(f.basis),
                    p_status: f.status !== 'all' ? f.status : null,
                    p_technician_id: f.technician !== 'all' ? f.technician : null,
                    p_search: search || null,
                    p_limit: 0,
                    p_offset: 0
                });

                if (response) {
                    if (response.counts) this.homeOperationalCounts = response.counts;
                    if (response.status_counts) this.homeStatusCounts = response.status_counts;
                    this.syncHomeOverviewQueues(response.queues || {});
                }
            } catch (error) {
                console.error('Failed to load home operational queue', error);
                this.notify('Erro ao carregar a Visão Geral.', 'error');
            } finally {
                this.homeOperationalLoading = false;
            }
        },

        async fetchKanbanOperationalCounts() {
            if (!this.user?.workspace_id) return;
            try {
                const f = this.kanbanOperationalFilters;
                const search = String(f.search || '').trim();

                const payload = {
                    p_window: f.window,
                    p_basis: f.basis,
                    p_status: f.status !== 'all' ? f.status : null,
                    p_technician_id: f.technician !== 'all' ? f.technician : null,
                    p_search: search ? search : null,
                    p_limit: 0, // Only fetch counts, no items
                    p_offset: 0
                };
                const response = await this.supabaseFetch('rpc/get_operational_queue', 'POST', payload);
                if (response && response.counts) {
                    this.kanbanOperationalCounts = response.counts;
                }
            } catch (e) {
                console.error("Failed to load kanban operational counts", e);
            }
        },

        // Helper to initialize filters for a column if not exists
        initColumnFilter(status) {
            if (!this.columnFilters[status]) {
                this.columnFilters[status] = {
                    sort: 'default', // default, priority, os, model
                    search: '',
                    dateStart: '',
                    dateEnd: '',
                    showMenu: false
                };
            }
            return this.columnFilters[status];
        },

        getSortedAndFilteredTickets(status) {
            // NOTE: matchesSearch is now mostly handled by server-side query if search is global.
            // But if we have local results, we still filter them for quick consistency.
            let list = this.tickets.filter(t => t.status === status);

            // Quick Filters (Local)
            if (this.activeQuickFilter) {
                list = list.filter(t => this.matchesQuickFilter(t));
            }

            // 2. Column Specific Filter (Local)
            const filter = this.columnFilters[status];
            if (filter) {
                if (filter.search) {
                    const q = filter.search.toLowerCase();
                    list = list.filter(t =>
                        (t.client_name && t.client_name.toLowerCase().includes(q)) ||
                        (t.os_number && t.os_number.toLowerCase().includes(q)) ||
                        (t.device_model && t.device_model.toLowerCase().includes(q)) ||
                        (t.serial_number && t.serial_number.toLowerCase().includes(q))
                    );
                }
                if (filter.dateStart) {
                    const start = new Date(filter.dateStart);
                    list = list.filter(t => new Date(t.created_at) >= start);
                }
                if (filter.dateEnd) {
                    const end = new Date(filter.dateEnd);
                    end.setHours(23, 59, 59);
                    list = list.filter(t => new Date(t.created_at) <= end);
                }
            }

            // 3. Sorting
            // Default Sort Rules
            const sortMode = filter ? filter.sort : 'default';

            list.sort((a, b) => {
                if (sortMode === 'priority') {
                    if (!this.isFieldVisible('priority')) return new Date(a.created_at) - new Date(b.created_at);
                    const pOrder = { 'Urgente': 0, 'Alta': 1, 'Normal': 2, 'Baixa': 3 };
                    return pOrder[a.priority] - pOrder[b.priority];
                }
                if (sortMode === 'os') {
                    return a.os_number.localeCompare(b.os_number, undefined, { numeric: true });
                }
                if (sortMode === 'model') {
                    return a.device_model.localeCompare(b.device_model);
                }

                // Default: prioridade solicitada -> agendamento aplicável -> prazo aplicável -> criação.
                const requestedA = this.isPriorityRequestEnabled() && Boolean(a.priority_requested);
                const requestedB = this.isPriorityRequestEnabled() && Boolean(b.priority_requested);
                if (requestedA !== requestedB) return requestedA ? -1 : 1;

                const appointmentA = this.getValidTimestamp(this.getBenchAppointmentDate(a));
                const appointmentB = this.getValidTimestamp(this.getBenchAppointmentDate(b));
                const deadlineA = this.getValidTimestamp(this.getBenchDeadlineDate(a));
                const deadlineB = this.getValidTimestamp(this.getBenchDeadlineDate(b));
                const createdA = this.getValidTimestamp(a.created_at) ?? Number.MAX_SAFE_INTEGER;
                const createdB = this.getValidTimestamp(b.created_at) ?? Number.MAX_SAFE_INTEGER;
                const effectiveA = appointmentA ?? deadlineA ?? createdA;
                const effectiveB = appointmentB ?? deadlineB ?? createdB;
                if (effectiveA !== effectiveB) return effectiveA - effectiveB;
                return createdA - createdB;
            });

            return list;
        },

        matchesSearch(ticket) {
            if (!this.searchQuery) return true;
            const q = this.searchQuery.toLowerCase();
            return (
                (ticket.client_name && ticket.client_name.toLowerCase().includes(q)) ||
                (ticket.os_number && ticket.os_number.toLowerCase().includes(q)) ||
                (ticket.device_model && ticket.device_model.toLowerCase().includes(q)) ||
                (ticket.serial_number && ticket.serial_number.toLowerCase().includes(q)) ||
                (ticket.contact_info && ticket.contact_info.toLowerCase().includes(q))
            );
        },

        matchesQuickFilter(ticket) {
            if (this.activeQuickFilter === 'my_today') {
                const oneDay = 24 * 60 * 60 * 1000;
                const isToday = new Date(ticket.created_at) > new Date(Date.now() - oneDay);
                const isMine = ticket.created_by_name === this.user.name;
                if (!isToday || !isMine) return false;
            }
            if (this.activeQuickFilter === 'stale_3d') {
                const threeDays = 3 * 24 * 60 * 60 * 1000;
                const isStale = new Date(ticket.updated_at) < new Date(Date.now() - threeDays);
                const isOpen = ticket.status !== 'Finalizado';
                if (!isStale || !isOpen) return false;
            }
            if (this.activeQuickFilter === 'priority') {
                if (!this.isPriorityRequestEnabled() || !ticket.priority_requested) return false;
            }
            if (this.activeQuickFilter === 'delayed') {
                if (!this.isFieldVisible('deadline')) return false;
                const now = new Date();
                const isDelayed = ticket.deadline && new Date(ticket.deadline) < now && !['Retirada Cliente', 'Finalizado'].includes(ticket.status);
                if (!isDelayed) return false;
            }
            return true;
        },

        getOverdueTime(deadline) {
            const diff = new Date() - new Date(deadline);
            const hours = Math.floor(diff / (1000 * 60 * 60));
            if (hours < 24) return `${hours}h`;
            const days = Math.floor(hours / 24);
            return `${days}d ${hours % 24}h`;
        },

        getOverviewQueueAge(ticket) {
            const enteredAt = ticket?.overview_queue_entered_at || ticket?.updated_at || ticket?.created_at || ticket?.entry_date;
            const enteredAtMs = new Date(enteredAt).getTime();
            if (!Number.isFinite(enteredAtMs)) return 'agora';

            const now = this.currentTime instanceof Date ? this.currentTime.getTime() : Date.now();
            const elapsedSeconds = Math.max(0, Math.floor((now - enteredAtMs) / 1000));

            if (elapsedSeconds < 60) return 'agora';
            if (elapsedSeconds < 3600) return 'há ' + Math.floor(elapsedSeconds / 60) + ' min';
            if (elapsedSeconds < 86400) return 'há ' + Math.floor(elapsedSeconds / 3600) + 'h';
            return 'há ' + Math.floor(elapsedSeconds / 86400) + 'd';
        },

        getDuration(startTime) {
            if (!startTime) return '00:00:00';
            const start = new Date(startTime).getTime();
            const now = this.currentTime.getTime();
            const diff = now - start;
            if (diff < 0) return '00:00:00';

            const h = Math.floor(diff / 3600000);
            const m = Math.floor((diff % 3600000) / 60000);
            const s = Math.floor((diff % 60000) / 1000);

            return `${h.toString().padStart(2,'0')}:${m.toString().padStart(2,'0')}:${s.toString().padStart(2,'0')}`;
        },

        getRepairDuration(ticket) {
            if (!ticket) return '00:00:00';
            let seconds = Number(ticket.repair_elapsed_seconds || 0);
            if (ticket.repair_start_at) {
                const elapsed = Math.floor((this.currentTime.getTime() - new Date(ticket.repair_start_at).getTime()) / 1000);
                seconds += Math.max(0, elapsed);
            }

            const h = Math.floor(seconds / 3600);
            const m = Math.floor((seconds % 3600) / 60);
            const s = seconds % 60;
            return `${h.toString().padStart(2,'0')}:${m.toString().padStart(2,'0')}:${s.toString().padStart(2,'0')}`;
        },

        toUTC(localDateString) {
            if (!localDateString) return null;
            return new Date(localDateString).toISOString();
        },

        openModal(name) {
            this.employeeForm = { name: '', username: '', password: '', roles: [] };
            this.modals[name] = true;
        },

        async createEmployee() {
            return await window.AIDAEmployeeService.createEmployee({
                state: this,
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload),
                notify: (msg, type) => this.notify(msg, type),
                setLoading: (val) => { this.loading = val; },
                fetchEmployees: () => this.fetchEmployees(),
                closeModal: (name) => { this.modals[name] = false; }
            });
        },

        openEditEmployee(emp) {
            this.employeeForm = {
                id: emp.id,
                name: emp.name,
                username: emp.username,
                password: '', // Password is never loaded
                roles: emp.roles || []
            };
            this.modals.editEmployee = true;
        },

        openResetPassword(emp) {
            this.resetPasswordForm = { employeeId: emp.id, newPassword: '', confirmPassword: '' };
            this.modals.resetPassword = true;
        },

        async resetEmployeePassword() {
            return await window.AIDAEmployeeService.resetEmployeePassword({
                state: this,
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload),
                notify: (msg, type) => this.notify(msg, type),
                setLoading: (val) => { this.loading = val; },
                closeModal: (name) => { this.modals[name] = false; }
            });
        },

        async changeOwnPassword() {
            return await window.AIDAEmployeeService.changeOwnPassword({
                state: this,
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload),
                notify: (msg, type) => this.notify(msg, type),
                setLoading: (val) => { this.loading = val; },
                validateSessionToken: (opts) => window.AIDAAuthSessionService.validateSessionToken(opts),
                bootstrapAuthenticatedApp: (opts) => this.bootstrapAuthenticatedApp(opts),
                processEmployeeLoginResponse: (result, companyCode, deps) => window.AIDAAuthSessionService.processEmployeeLoginResponse(result, companyCode, deps),
                closeModal: (name) => { this.modals[name] = false; }
            });
        },

        async updateEmployee() {
            return await window.AIDAEmployeeService.updateEmployee({
                state: this,
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload),
                notify: (msg, type) => this.notify(msg, type),
                setLoading: (val) => { this.loading = val; },
                fetchEmployees: () => this.fetchEmployees(),
                closeModal: (name) => { this.modals[name] = false; }
            });
        },

        async deleteEmployee(id) {
            return await window.AIDAEmployeeService.deleteEmployee(id, {
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload),
                notify: (msg, type) => this.notify(msg, type),
                fetchEmployees: () => this.fetchEmployees()
            });
        },

        _getRecycleBinDeps() {
            return {
                state: this,
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload),
                hasRole: (r) => this.hasRole(r),
                setLoading: (val) => { this.loading = val; },
                notify: (msg, type) => this.notify(msg, type),
                mutateTicket: (t, act, upd, log, opts) => this.mutateTicket(t, act, upd, log, opts),
                fetchDeletedItems: () => this.fetchDeletedItems(),
                fetchEmployees: () => this.fetchEmployees()
            };
        },

        async fetchDeletedItems() {
            return await window.AIDARecycleBinService.fetchDeletedItems(this._getRecycleBinDeps());
        },

        openRecycleBin() {
            this.fetchDeletedItems();
            this.modals.recycleBin = true;
        },

        formatDuration(ms) {
            const n = Number(ms);
            if (ms === null || ms === undefined || Number.isNaN(n)) return '-';
            if (n < 0) return '-';

            const totalMinutes = Math.round(n / 60000);
            const days = Math.floor(totalMinutes / 1440);
            const hours = Math.floor((totalMinutes % 1440) / 60);
            const minutes = totalMinutes % 60;

            const parts = [];
            if (days) parts.push(`${days}d`);
            if (hours || days) parts.push(`${hours}h`);
            parts.push(`${minutes}m`);
            return parts.join(' ');
        },

        toArray(value) {
            if (!value) return [];
            if (Array.isArray(value)) return value;
            return [value];
        },

        hasRole(role) {
            if (this.session && role === 'admin') return true;
            if (!this.user) return false;
            const roles = this.user.roles || [];
            if (roles.includes('admin')) return true;
            return roles.includes(role);
        },

        notify(message, type = 'success') {
            const id = Date.now();
            this.notifications.push({ id, message, type });
            setTimeout(() => { this.notifications = this.notifications.filter(n => n.id !== id); }, 3000);
        }
    }
}

