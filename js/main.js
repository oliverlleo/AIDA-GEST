
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
            customization: {
                workflow: false,
                modules: false,
                ticket_fields: false,
                overview: false
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
        benchCalendarMode: 'appointment', // 'appointment' is the default; 'deadline' remains selectable

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
        schedulePanelTicket: null,
        schedulePanelTechnicianId: null,
        schedulePanelAfterSave: null,
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
            'Analise Tecnica': 'Análise Técnica',
            'Aprovacao': 'Aprovação',
            'Compra Peca': 'Compra de Peças',
            'Andamento Reparo': 'Em Reparo',
            'Teste Final': 'Testes Finais',
            'Retirada Cliente': 'Retirada de Cliente',
            'Finalizado': 'Finalizado'
        },

        // REQUIRED FIELDS DEFINITION
        TICKET_REQUIRED_FIELDS: [
            { key: 'client_name', label: 'Cliente', icon: 'fa-user', col: 'client_name', type: 'text' },
            { key: 'contact_info', label: 'Contato', icon: 'fa-phone', col: 'contact_info', type: 'text' },
            { key: 'os_number', label: 'Nº OS (Manual)', icon: 'fa-hashtag', col: 'os_number', type: 'text' },
            { key: 'serial_number', label: 'Nº Série / IMEI', icon: 'fa-barcode', col: 'serial_number', type: 'text' },
            { key: 'priority', label: 'Prioridade', icon: 'fa-flag', col: 'priority', type: 'text' },
            { key: 'device_model', label: 'Modelo', icon: 'fa-mobile-screen-button', col: 'device_model', type: 'text' },
            { key: 'analysis_deadline', label: 'Prazo de Análise', icon: 'fa-hourglass-half', col: 'analysis_deadline', type: 'date' },
            { key: 'deadline', label: 'Prazo de Entrega', icon: 'fa-calendar-check', col: 'deadline', type: 'date' },
            { key: 'device_condition', label: 'Situação do Aparelho', icon: 'fa-mobile-screen', col: 'device_condition', type: 'text' },
            { key: 'responsible', label: 'Técnico Responsável', icon: 'fa-user-gear', col: 'technician_id', type: 'id_check' },
            { key: 'defect_reported', label: 'Defeito Relatado', icon: 'fa-triangle-exclamation', col: 'defect_reported', type: 'text' },
            { key: 'checklist_entry', label: 'Checklist de Entrada', icon: 'fa-clipboard-check', col: 'checklist_data', type: 'array' },
            { key: 'checklist_exit', label: 'Checklist de Saída', icon: 'fa-clipboard-list', col: 'checklist_final_data', type: 'array' },
            { key: 'photos', label: 'Fotos', icon: 'fa-camera', col: 'photos_urls', type: 'array' },
            { key: 'analysis_schedule', label: 'Agendamento de Análise', icon: 'fa-calendar-day', col: 'analysis_schedule', type: 'schedule' },
            { key: 'repair_schedule', label: 'Agendamento de Reparo', icon: 'fa-calendar-plus', col: 'repair_schedule', type: 'schedule' }
        ],

        // ==========================================
        // SCHEDULING FACTORIES
        // ==========================================
        getDefaultScheduleEditingAppointment() {
            return {
                ticket_id: '',
                type: 'analysis',
                original: null,
                ticketContext: null,
                new_date: '',
                new_start: '',
                new_end: '',
                new_technician_id: '',
                notes: ''
            };
        },

        getDefaultScheduleEditingBlock() {
            return {
                block_id: null,
                date: '',
                start: '',
                end: '',
                full_day: false,
                is_recurring: false,
                recurrence_type: 'daily',
                recurrence_end_date: '',
                notes: ''
            };
        },

        // ==========================================
        // CONFIG HELPERS (TRACKER / FEATURES)
        // ==========================================
        isLogisticsEnabled() {
            return window.AIDAConfigHelpers.isLogisticsEnabled(this.trackerConfig);
        },
        isOutsourcedEnabled() {
            return window.AIDAConfigHelpers.isOutsourcedEnabled(this.trackerConfig);
        },
        getTestFlowMode() {
            return window.AIDAConfigHelpers.getTestFlowMode(this.trackerConfig);
        },
        isAutoOSGenerationEnabled() {
            return window.AIDAConfigHelpers.isAutoOSGenerationEnabled(this.trackerConfig);
        },
        isWhatsAppDisabled() {
            return window.AIDAConfigHelpers.isWhatsAppDisabled(this.trackerConfig);
        },
        isRequiredFieldsEnabled() {
            return window.AIDAConfigHelpers.isRequiredFieldsEnabled(this.trackerConfig);
        },
        normalizeFeatureConfig() {
            this.trackerConfig = window.AIDAFeatureConfig.normalize(this.trackerConfig);
            if (!this.isModuleEnabled('agenda')) {
                this.modals.calendar = false;
                this.closeSchedulePanel();
                if (this.isFieldVisible('deadline')) this.benchCalendarMode = 'deadline';
            } else if (!this.isFieldVisible('deadline') && (this.isAppointmentTypeEnabled('analysis') || this.isAppointmentTypeEnabled('repair'))) {
                this.benchCalendarMode = 'appointment';
            } else if (this.benchCalendarMode === 'appointment' && !this.isAppointmentTypeEnabled('analysis') && !this.isAppointmentTypeEnabled('repair')) {
                this.benchCalendarMode = 'deadline';
            }
            return this.trackerConfig;
        },
        getFieldMode(key) {
            return window.AIDAFeatureConfig.getFieldMode(this.trackerConfig, key);
        },
        setFieldMode(key, mode) {
            this.trackerConfig = window.AIDAFeatureConfig.setFieldMode(this.trackerConfig, key, mode);
        },
        isCustomizationEnabled(key) {
            return window.AIDAFeatureConfig.isCustomizationEnabled(this.trackerConfig, key);
        },
        setCustomizationEnabled(key, enabled) {
            this.trackerConfig = window.AIDAFeatureConfig.setCustomizationEnabled(this.trackerConfig, key, enabled);
            this.normalizeFeatureConfig();
        },
        isFieldVisible(key) {
            return window.AIDAConfigHelpers.isFieldVisible(this.trackerConfig, key);
        },
        isPartsControlEnabled() {
            return window.AIDAConfigHelpers.isPartsControlEnabled(this.trackerConfig);
        },
        isFinalTestEnabled() {
            return window.AIDAConfigHelpers.isFinalTestEnabled(this.trackerConfig);
        },
        isTimerEnabled(type) {
            return window.AIDAConfigHelpers.isTimerEnabled(this.trackerConfig, type);
        },
        getDeliveryMode() {
            return window.AIDAConfigHelpers.getDeliveryMode(this.trackerConfig);
        },
        isPriorityRequestEnabled() {
            return window.AIDAConfigHelpers.isPriorityRequestEnabled(this.trackerConfig);
        },
        isModuleEnabled(key) {
            return window.AIDAConfigHelpers.isModuleEnabled(this.trackerConfig, key);
        },
        isOverviewSectionEnabled(key) {
            return window.AIDAConfigHelpers.isOverviewSectionEnabled(this.trackerConfig, key);
        },
        isAppointmentTypeEnabled(type) {
            return window.AIDAConfigHelpers.isAppointmentTypeEnabled(this.trackerConfig, type);
        },
        getEffectiveOperationalBasis(basis = 'auto') {
            const analysisEnabled = this.isFieldVisible('analysis_deadline');
            const deliveryEnabled = this.isFieldVisible('deadline');
            if (basis === 'analysis' && !analysisEnabled) return deliveryEnabled ? 'delivery' : 'entry';
            if (basis === 'delivery' && !deliveryEnabled) return analysisEnabled ? 'analysis' : 'entry';
            if (basis === 'auto' && !analysisEnabled && !deliveryEnabled) return 'entry';
            return basis;
        },

        // ==========================================
        // MODAL CONTEXT / ACTIVE TICKET HELPER
        // ==========================================

        // Wrapper for context actions
        _applyContext(contextState) {
            this.activeTicketId = contextState.activeTicketId;
            this.activeModalContext = contextState.activeModalContext;
        },

        resolveTicket(ticketOrId) {
            return window.AIDATicketContext.resolveTicket(
                ticketOrId,
                this.tickets,
                this.selectedTicket
            );
        },

        // --- HELPER: NATIVE FETCH (Stateless) ---
        async supabaseFetch(endpoint, method = 'GET', body = null, requestOptions = {}) {
            return await window.AIDAApiClient.supabaseFetch(endpoint, method, body, {
                SUPABASE_URL,
                SUPABASE_KEY,
                state: this
            }, requestOptions);
        },

        // --- STORAGE HELPER ---
        getStorageHeaders(contentType) {
            return window.AIDAStorageService.getStorageHeaders(contentType, {
                SUPABASE_KEY,
                state: this
            });
        },

        // ==========================================
        // CARREGAMENTO & POLÍTICAS DE ATUALIZAÇÃO
        // ==========================================

        // --- 1. BOOTSTRAP CENTRAL ---
        async bootstrapAuthenticatedApp(options = {}) {
            if (this.bootstrapInFlight) return;
            this.bootstrapInFlight = true;
            this.bootstrapDone = false;

            try {
                // 1. Ensure Base Catalogs & Data
                await this.ensureBaseDataLoaded();

                // Initialize context variables now that employees are loaded
                this.initTechFilter();

                // 2. Load Core Application Data for Current View
                await this.loadDataForCurrentView(true); // force load current view initially

                this.bootstrapDone = true;
            } catch (err) {
                console.error("[Bootstrap] Failed:", err);
                this.notify("Erro ao carregar os dados iniciais do aplicativo.", "error");
            } finally {
                this.bootstrapInFlight = false;
            }
        },

        // --- 2. BASE LOAD CENTRAL ---
        async ensureBaseDataLoaded() {
            if (this.baseDataLoaded) return;

            try {
                // Start parallel fetching for core static/catalog data
                await Promise.all([
                    this.fetchEmployees(),
                    this.fetchTemplates(),
                    this.fetchDeviceModels(),
                    this.fetchDefectOptions(),
                    this.fetchOutsourcedCompanies(),
                    this.isModuleEnabled('suppliers') ? this.fetchFornecedores() : Promise.resolve()
                ]);

                // Initial global logs load
                this.fetchGlobalLogs();

                // Setup realtime
                if (!this.realtimeReady) {
                    this.setupRealtime();
                    this.realtimeReady = true;
                }

                this.baseDataLoaded = true;
            } catch (err) {
                console.error("[EnsureBaseData] Error:", err);
                throw err;
            }
        },

        // --- 3. CARREGAMENTO DEPENDENTE DA VIEW ---
        async loadDataForCurrentView(force = false) {
            let currentView = this.view;

            const disabledView =
                (currentView === 'schedule_management' && !this.isModuleEnabled('agenda'))
                || (currentView === 'admin_dashboard' && !this.isModuleEnabled('manager_dashboard'))
                || (currentView === 'tracker_settings' && !this.isModuleEnabled('public_tracker'));
            if (disabledView) {
                currentView = 'dashboard';
                this.view = 'dashboard';
            }

            // Blindagem mínima contra view de dashboard indevida no primeiro acesso de técnicos/testers
            if (currentView === 'dashboard' && this.user) {
                // IMPORTANT: Read purely from the user roles array, bypassing the global hasRole() function
                // to avoid false positives caused by lingering 'this.session' evaluations.
                const roles = this.user.roles || [];
                const isTech = roles.includes('tecnico');
                const isTester = roles.includes('tester');
                const isAdminOrAttendant = roles.includes('admin') || roles.includes('atendente');

                const isTesterOnly = isTester && !isAdminOrAttendant;
                const isTechOnly = isTech && !isAdminOrAttendant;

                if (isTesterOnly) {
                    currentView = 'tester_bench';
                    this.view = 'tester_bench';
                } else if (isTechOnly) {
                    currentView = 'tech_orders';
                    this.view = 'tech_orders';
                }
            }

            // Manage View-Specific State Resets (Runs every time view changes)
            if (currentView === 'kanban') {
                setTimeout(() => this.initKanbanScroll(), 100);
            } else if (!['dashboard', 'admin_dashboard', 'kanban'].includes(currentView)) {
                // Ensure other views start with clear filters
                this.searchQuery = '';
                this.activeQuickFilter = null;
                this.columnFilters = {};
            }

            // NOTA SOBRE CACHE (viewsLoaded): Não podemos pular `fetchTickets()` pois
            // a lista global de `tickets` muda conforme o contexto da tela (Dashboard vs Kanban vs Tech Orders).
            // O cache serve apenas para dados secundários, mas a engine primária precisa rodar.

            try {
                if (currentView === 'dashboard') {
                    await this.fetchTickets();
                    // Logs estáticos podem usar o cache
                    if (!this.viewsLoaded[currentView]) {
                        this.fetchGlobalLogs();
                    }
                    await this.requestDashboardMetrics({ reason: 'view_change' });
                    await this.fetchHomeOperationalQueue();
                } else if (currentView === 'admin_dashboard') {
                    await this.fetchTickets();
                    await this.requestDashboardMetrics({ reason: 'open_admin_dashboard' });
                } else if (currentView === 'kanban') {
                    await this.fetchTickets();
                    await this.fetchOperationalAlerts(); // Alerts are used in kanban header
                    await this.fetchKanbanOperationalCounts();
                } else {
                    // Outras views (tech_orders, tester_bench, etc.)
                    await this.fetchTickets();
                }

                // Mark view as loaded for secondary unshared resources
                if (this.viewsLoaded.hasOwnProperty(currentView)) {
                    this.viewsLoaded[currentView] = true;
                }
            } catch (e) {
                console.error(`Erro ao carregar dados da view: ${currentView}`, e);
            }
        },

        async init() {
            if (this.initInFlight) return;
            this.initInFlight = true;

            // Pre-calculate status index map for O(1) lookups
            this.STATUS_INDEX_MAP = this.STATUS_COLUMNS.reduce((acc, status, idx) => {
                acc[status] = idx;
                return acc;
            }, {});

            console.log("App initializing...");
            this.loading = true;

            if (!supabaseClient) {
                this.error = "Erro de Configuração: As credenciais do Supabase não foram encontradas. Certifique-se de configurar o arquivo js/supabase-config.js corretamente.";
                this.notify("Erro crítico: Supabase não configurado.", "error");
                this.loading = false;
                return;
            }

            try {
                const { data: { session } } = await supabaseClient.auth.getSession();
                if (session) {
                    this.session = session;
                    await this.loadAdminData();
                } else {
                    const storedEmp = localStorage.getItem('techassist_employee');
                    if (storedEmp) {
                        try {
                            this.employeeSession = JSON.parse(storedEmp);

                            // Validate Session Token
                            if (this.employeeSession.token) {
                                const freshSession = await window.AIDAAuthSessionService.validateSessionToken({
                                    state: this,
                                    supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload)
                                });

                                if (!freshSession) {
                                    this.logout();
                                    return;
                                }

                                // FORCE UPDATE from Server Truth
                                this.employeeSession.workspace_id = freshSession.workspace_id;
                                this.employeeSession.employee_id = freshSession.employee_id;
                                this.employeeSession.roles = freshSession.roles || [];
                                if (!this.employeeSession.id) this.employeeSession.id = freshSession.employee_id;

                                // Update Storage with trusted data
                                localStorage.setItem('techassist_employee', JSON.stringify(this.employeeSession));
                            } else {
                                // Legacy session without token
                                console.warn("Legacy session detected. Logging out.");
                                this.logout();
                                return;
                            }

                            this.user = this.employeeSession;
                            if (this.employeeSession.workspace_name) this.workspaceName = this.employeeSession.workspace_name;
                            if (this.employeeSession.company_code) this.companyCode = this.employeeSession.company_code;

                            // Correção Bug 5: O Telefone da empresa salva, mas não reaparecia para funcionários ou em reload.
                            // Hidratar whatsappNumber no front a partir da sessão armazenada, se disponível.
                            if (this.employeeSession.whatsapp_number) this.whatsappNumber = this.employeeSession.whatsapp_number;

                            // Restore Tracker Config
                            if (this.employeeSession.tracker_config) {
                                this.trackerConfig = window.AIDAFeatureConfig.normalize({
                                    ...this.trackerConfig,
                                    ...this.employeeSession.tracker_config,
                                    colors: {
                                        ...this.trackerConfig.colors,
                                        ...(this.employeeSession.tracker_config.colors || {})
                                    },
                                    // Merge new fields if they don't exist in saved config
                                    required_ticket_fields: {
                                        ...this.trackerConfig.required_ticket_fields,
                                        ...(this.employeeSession.tracker_config.required_ticket_fields || {})
                                    }
                                });
                            }
                            this.normalizeFeatureConfig();

                            // CHECK MUST CHANGE PASSWORD
                            if (this.employeeSession.must_change_password) {
                                this.mustChangePassword = true;
                                this.modals.forceChangePassword = true;
                            }

                            // Redirect Technician to Tech Bench on reload
                            if (this.hasRole('tecnico') && !this.hasRole('admin') && !this.hasRole('atendente')) {
                                this.view = 'tech_orders';
                            }
                        } catch (e) {
                            console.error("Session restore error:", e);
                            localStorage.removeItem('techassist_employee');
                        }
                    }
                }

                if (this.user) {
                    // Block access if must change password
                    if (this.mustChangePassword) return;

                    await this.bootstrapAuthenticatedApp({ reason: 'init_restore' });
                }
            } catch (err) {
                console.error("Init Error:", err);
            } finally {
                this.loading = false;
                this.initInFlight = false;
            }

            supabaseClient.auth.onAuthStateChange(async (_event, session) => {
                this.session = session;
                if (session) {
                    await this.loadAdminData();
                } else if (!this.employeeSession) {
                    this.user = null;
                }
            });

            setInterval(() => {
                this.currentTime = new Date();
            }, 1000);

            setInterval(() => {
                this.checkTimeBasedAlerts();
            }, 60000);

            this.$watch('view', (value) => {
                this.loadDataForCurrentView();
            });

            this.$watch('searchQuery', () => {
                this.handleSearchInput();
            });

            this.$watch('showFinalized', () => {
                this.finalizedPage = 0;
                this.fetchTickets();
            });

            this.$watch('adminDashboardFilters', () => {
                // If filters change, reload dashboard metrics AND list
                if (this.adminDashboardFilters.quickView === 'daily_report') {
                    this.requestDailyReport();
                } else {
                    this.requestDashboardMetrics({ reason: 'filters' });
                }
                this.fetchTickets();
            });
        },

        // --- OPTIMIZED DASHBOARD REQUEST ---
        async requestDashboardMetrics({ reason = 'init' } = {}) {
            if (!this.user?.workspace_id) return;

            const now = Date.now();

            // 1. Throttle for Realtime (1500ms)
            if (reason === 'realtime') {
                const timeSinceLast = now - this.lastDashboardCallTime;
                const THROTTLE_MS = 1500;

                if (timeSinceLast < THROTTLE_MS) {
                    if (this.dashboardThrottleTimer) return; // Already scheduled
                    const delay = THROTTLE_MS - timeSinceLast;
                    console.log(`[Dashboard][Realtime] throttled (wait ${delay} ms)`);
                    this.dashboardThrottleTimer = setTimeout(() => {
                        this.dashboardThrottleTimer = null;
                        this.requestDashboardMetrics({ reason: 'realtime' });
                    }, delay);
                    return;
                }
            }

            // Clear any pending throttle if we are executing now
            if (this.dashboardThrottleTimer) {
                clearTimeout(this.dashboardThrottleTimer);
                this.dashboardThrottleTimer = null;
            }

            // 2. Prepare Params
            const f = this.adminDashboardFilters;

            // garante período mesmo se só um lado vier preenchido
            const dateStart = f.dateStart || f.dateEnd || null;
            const dateEnd = f.dateEnd || f.dateStart || null;

            const params = {
                p_date_start: dateStart,
                p_date_end: dateEnd,
                p_technician_id: f.technician === 'all' ? null : f.technician,
                p_status: f.status === 'all' ? null : f.status,
                p_defect: f.defect === 'all' ? null : f.defect,
                p_device_model: f.deviceModel === 'all' ? null : f.deviceModel,
                p_search: this.searchQuery || null
            };
            // Generate key including workspace_id to ensure uniqueness across users
            const paramString = JSON.stringify({ ...params, ws: this.user.workspace_id });

            // 3. Deduplication (In-flight)
            if (this.dashboardMetricsPromise) {
                // If a realtime request comes in while we are loading, mark it pending so we refresh AGAIN after.
                if (reason === 'realtime') {
                    console.log('[Dashboard][Realtime] joining in-flight (marking pending refresh)');
                    this.pendingRealtimeRefresh = true;
                } else {
                    console.log(`[Dashboard] Waiting for in-flight request (${reason})`);
                }

                return this.dashboardMetricsPromise;
            }

            // 4. Cache / Skip Duplicate calls
            const CACHE_TTL = 5000;
            const isCacheValid = (now - this.lastDashboardCallTime) < CACHE_TTL;

            if (reason !== 'realtime' && this.lastDashboardParams === paramString && isCacheValid) {
                console.log(`[Dashboard] skip duplicate/cached reason=${reason}`);
                return;
            }

            // 5. Execute
            console.log(`[Dashboard] RPC call reason=${reason} key=${paramString.slice(0, 20)}...`);

            this.dashboardMetricsPromise = (async () => {
                try {
                    // The Overview has its own compact queue summary.
                    // Operational alert lists are loaded only by the Kanban view.
                    // Delegate to the dashboard service
                    const data = await window.AIDADashboardService.requestDashboardMetrics(params, {
                        supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload)
                    });

                    if (data) {
                        this.metrics = { ...this.metrics, ...data };
                        this.lastDashboardParams = paramString;
                        this.lastDashboardCallTime = Date.now();

                        // Refresh Charts if visible
                        if (this.adminDashboardFilters.viewType === 'chart') {
                            setTimeout(() => this.renderCharts(), 50);
                        }
                    }
                } catch (e) {
                    console.error("Dashboard Error:", e);
                    this.notify("Erro ao carregar métricas.", "error");
                } finally {
                    this.dashboardMetricsPromise = null;

                    if (this.pendingRealtimeRefresh) {
                        this.pendingRealtimeRefresh = false;
                        this.requestDashboardMetrics({ reason: 'realtime' });
                    }
                }
            })();

            return this.dashboardMetricsPromise;
        },

        // Explicitly invalidate cache to force a fresh fetch on next request
        invalidateDashboardCache(reason) {
            this.lastDashboardCallTime = 0;
            this.lastDashboardParams = null;
            console.log('[Dashboard] cache invalidated reason=' + reason);
        },

        // Backward compatibility / Alias if needed
        async calculateMetrics() {
            await this.requestDashboardMetrics({ reason: 'legacy_call' });
        },

        async requestDailyReport() {
            if (!this.user?.workspace_id) return;
            this.dailyReportLoading = true;
            this.dailyReportError = null;

            try {
                const f = this.adminDashboardFilters;
                const params = {
                    p_date_start: f.dateStart || null,
                    p_date_end: f.dateEnd || null
                };

                const data = await window.AIDADashboardService.requestDailyReport(params, {
                    supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload)
                });

                if (data) {
                    this.dailyReport = data;
                } else {
                    this.dailyReportError = "Nenhum dado retornado.";
                }
            } catch (e) {
                console.error("Daily Report Error:", e);
                this.dailyReportError = e.message;
            } finally {
                this.dailyReportLoading = false;
            }
        },

        toggleAdminView() {
            this.adminDashboardFilters.viewType = this.adminDashboardFilters.viewType === 'data' ? 'chart' : 'data';
            this.requestDashboardMetrics({ reason: 'view_toggle' });
            if (this.adminDashboardFilters.viewType === 'chart') {
                setTimeout(() => this.renderCharts(), 50);
            }
        },

        chartInstances: {},

        renderCharts() {
            if (typeof Chart === 'undefined') return;

            const destroy = (id) => {
                if (this.chartInstances[id]) {
                    this.chartInstances[id].destroy();
                    delete this.chartInstances[id];
                }
            };

            const metrics = this.metrics;
            const commonOptions = { responsive: true, maintainAspectRatio: false };

            // 1. Repairs Over Time
            destroy('repairsChart');
            const repairsCtx = document.getElementById('repairsChart');
            if (repairsCtx) {
                this.chartInstances.repairsChart = new Chart(repairsCtx, {
                    type: 'bar',
                    data: {
                        labels: ['Hoje', 'Semana', 'Mês'],
                        datasets: [{
                            label: 'Reparos Finalizados',
                            data: [metrics.repairsToday, metrics.repairsWeek, metrics.repairsMonth],
                            backgroundColor: 'rgba(255, 107, 0, 0.6)',
                            borderColor: 'rgba(255, 107, 0, 1)',
                            borderWidth: 1
                        }]
                    },
                    options: { ...commonOptions, scales: { y: { beginAtZero: true, ticks: { stepSize: 1 } } } }
                });
            }

            // 2. Tickets Created Over Time
            destroy('ticketsChart');
            const ticketsCtx = document.getElementById('ticketsChart');
            if (ticketsCtx) {
                this.chartInstances.ticketsChart = new Chart(ticketsCtx, {
                    type: 'bar',
                    data: {
                        labels: ['Hoje', 'Semana', 'Mês'],
                        datasets: [{
                            label: 'Chamados Criados',
                            data: [metrics.ticketsToday, metrics.ticketsWeek, metrics.ticketsMonth],
                            backgroundColor: 'rgba(59, 130, 246, 0.6)',
                            borderColor: 'rgba(59, 130, 246, 1)',
                            borderWidth: 1
                        }]
                    },
                    options: { ...commonOptions, scales: { y: { beginAtZero: true, ticks: { stepSize: 1 } } } }
                });
            }

            // 3. Top Defects
            destroy('defectsChart');
            const defectsCtx = document.getElementById('defectsChart');
            if (defectsCtx && metrics.topDefects.length) {
                this.chartInstances.defectsChart = new Chart(defectsCtx, {
                    type: 'doughnut',
                    data: {
                        labels: metrics.topDefects.slice(0, 5).map(d => d.label),
                        datasets: [{
                            data: metrics.topDefects.slice(0, 5).map(d => d.total),
                            backgroundColor: ['#FF6B00', '#3B82F6', '#10B981', '#F59E0B', '#EF4444']
                        }]
                    },
                    options: commonOptions
                });
            }

            // 4. Tech Efficiency
            destroy('techChart');
            const techCtx = document.getElementById('techChart');
            if (techCtx && metrics.techStats.length) {
                this.chartInstances.techChart = new Chart(techCtx, {
                    type: 'bar',
                    data: {
                        labels: metrics.techStats.map(t => t.name),
                        datasets: [
                            {
                                label: 'Volume Total',
                                data: metrics.techStats.map(t => t.total),
                                backgroundColor: 'rgba(156, 163, 175, 0.5)',
                                yAxisID: 'y'
                            },
                            {
                                label: 'Taxa Sucesso (%)',
                                data: metrics.techStats.map(t => t.successRate),
                                type: 'line',
                                borderColor: '#10B981',
                                tension: 0.1,
                                yAxisID: 'y1'
                            }
                        ]
                    },
                    options: {
                        ...commonOptions,
                        scales: {
                            y: { beginAtZero: true, position: 'left' },
                            y1: { beginAtZero: true, position: 'right', max: 100, grid: { drawOnChartArea: false } }
                        }
                    }
                });
            }

            // 5. Solution Time by Model (New)
            destroy('solutionTimeChart');
            const solutionCtx = document.getElementById('solutionTimeChart');
            if (solutionCtx && metrics.slowestModelsSolution.length) {
                this.chartInstances.solutionTimeChart = new Chart(solutionCtx, {
                    type: 'bar',
                    data: {
                        labels: metrics.slowestModelsSolution.map(m => m.label),
                        datasets: [{
                            label: 'Tempo Médio Solução (min)',
                            data: metrics.slowestModelsSolution.map(m => Math.round(m.avgTime / 60000)),
                            backgroundColor: 'rgba(59, 130, 246, 0.6)'
                        }]
                    },
                    options: { ...commonOptions, indexAxis: 'y' }
                });
            }

            // 6. Delivery Time by Model (New)
            destroy('deliveryTimeChart');
            const deliveryCtx = document.getElementById('deliveryTimeChart');
            if (deliveryCtx && metrics.slowestModelsDelivery.length) {
                this.chartInstances.deliveryTimeChart = new Chart(deliveryCtx, {
                    type: 'bar',
                    data: {
                        labels: metrics.slowestModelsDelivery.map(m => m.label),
                        datasets: [{
                            label: 'Tempo Médio Entrega (horas)',
                            data: metrics.slowestModelsDelivery.map(m => Math.round(m.avgTime / 3600000)),
                            backgroundColor: 'rgba(16, 185, 129, 0.6)'
                        }]
                    },
                    options: { ...commonOptions, indexAxis: 'y' }
                });
            }

            // 7. Success Rate by Model (New)
            destroy('modelSuccessChart');
            const modelSuccessCtx = document.getElementById('modelSuccessChart');
            if (modelSuccessCtx && metrics.topModels.length) {
                const top5 = metrics.topModels.slice(0, 5);
                this.chartInstances.modelSuccessChart = new Chart(modelSuccessCtx, {
                    type: 'bar',
                    data: {
                        labels: top5.map(m => m.label),
                        datasets: [
                            {
                                label: 'Sucesso',
                                data: top5.map(m => m.success),
                                backgroundColor: '#10B981'
                            },
                            {
                                label: 'Falha',
                                data: top5.map(m => m.fail),
                                backgroundColor: '#EF4444'
                            }
                        ]
                    },
                    options: { ...commonOptions, scales: { x: { stacked: true }, y: { stacked: true } } }
                });
            }
        },

        setupRealtime() {
            if (!this.user?.workspace_id || !supabaseClient) return;
            if (this.session && !this.session.user) return; // Ensure session is fully ready if applicable

            const channels = [
                {
                    topic: 'tickets_channel',
                    setup: (c) => c.on('postgres_changes', { event: '*', schema: 'public', table: 'tickets' }, (payload) => this.handleRealtimeUpdate(payload))
                },
                {
                    topic: 'notifications_channel',
                    setup: (c) => c.on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'notifications' }, () => this.fetchNotifications())
                },
                {
                    topic: 'ticket_logs_channel',
                    setup: (c) => c.on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'ticket_logs' }, () => this.fetchGlobalLogs())
                }
            ];

            channels.forEach(({ topic, setup }) => {
                const existing = supabaseClient.getChannels().find(c => c.topic === topic);

                if (existing) {
                    if (['joined', 'joining', 'subscribed'].includes(existing.state)) {
                        console.log(`[RT] channel reused (${topic}) state=${existing.state}`);
                        return;
                    } else {
                        console.log(`[RT] channel recreating (${topic}) was=${existing.state}`);
                        supabaseClient.removeChannel(existing);
                    }
                }

                const channel = supabaseClient.channel(topic);
                setup(channel).subscribe((status) => {
                    if (status === 'SUBSCRIBED') {
                        console.log(`[RT] subscribed (${topic})`);
                    } else if (status === 'CHANNEL_ERROR') {
                        if (!isUnloading) console.error(`[RT] error (${topic})`);
                    }
                });
            });
        },

        // --- AUTH & SESSION ---

        // Helper to provide dependencies for auth service
        _getAuthDeps() {
            return {
                state: this,
                supabaseClient: supabaseClient,
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload),
                notify: (msg, type) => this.notify(msg, type),
                setLoading: (val) => { this.loading = val; },
                hasRole: (r) => this.hasRole(r),
                validateSessionToken: (opts) => window.AIDAAuthSessionService.validateSessionToken(opts),
                bootstrapAuthenticatedApp: (opts) => this.bootstrapAuthenticatedApp(opts),
                _applyContext: (ctx) => this._applyContext(ctx)
            };
        },

        async loginAdmin() {
            return await window.AIDAAuthSessionService.loginAdmin(this._getAuthDeps());
        },

        async registerAdmin() {
            return await window.AIDAAuthSessionService.registerAdmin(this._getAuthDeps());
        },

        async completeCompanySetup() {
            return await window.AIDAAuthSessionService.completeCompanySetup(this._getAuthDeps());
        },

        async loginEmployee() {
            return await window.AIDAAuthSessionService.loginEmployee(this._getAuthDeps());
        },

        async logout() {
            return await window.AIDAAuthSessionService.logout(this._getAuthDeps());
        },

        async loadAdminData() {
            return await window.AIDAAuthSessionService.loadAdminData(this._getAuthDeps());
        },
        async fetchEmployees() {
            return await window.AIDAEmployeeService.fetchEmployees({
                state: this,
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload)
            });
        },

        // --- COMPANY CONFIG ---
        async saveCompanyConfig() {
            return await window.AIDAWorkspaceConfigService.saveCompanyConfig({
                state: this,
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload),
                notify: (msg, type) => this.notify(msg, type),
                setLoading: (val) => { this.loading = val; }
            });
        },

        // --- TRACKER CONFIG ACTIONS (NEW) ---
        async saveTrackerConfig() {
            return await window.AIDAWorkspaceConfigService.saveTrackerConfig({
                state: this,
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload),
                notify: (msg, type) => this.notify(msg, type),
                setLoading: (val) => { this.loading = val; },
                fetchTickets: () => this.fetchTickets()
            });
        },

        async handleLogoUpload(event) {
            const file = event.target.files[0];
            if (!file) return;

            this.loading = true;
            try {
                const publicUrl = await window.AIDAStorageService.handleLogoUpload(file, {
                    SUPABASE_URL,
                    SUPABASE_KEY,
                    state: this
                });

                this.trackerConfig.logo_url = publicUrl;
                this.notify("Logo carregado!");
            } catch(e) {
                this.notify("Erro upload: " + e.message, "error");
            } finally {
                this.loading = false;
            }
        },

        handleLogoRemove() {
            this.trackerConfig.logo_url = '';
        },

        resetTrackerStages() {
            if (confirm("Deseja restaurar os nomes originais das etapas?")) {
                this.trackerConfig.custom_labels = {};
                this.notify("Nomes restaurados (Salvar para aplicar)");
            }
        },

        resetTrackerConfig() {
            if (confirm("Deseja redefinir toda a configuração da página de acompanhamento?")) {
                this.trackerConfig = {
                    logo_url: '',
                    logo_size: 64,
                    enable_logistics: false,
                    custom_labels: {},
                    colors: {
                        background: '#FFF7ED',
                        card_bg: '#FFFFFF',
                        header_bg: '#000000',
                        text_primary: '#1a1a1a',
                        text_secondary: '#6B7280',
                        progress_bar: '#FF6B00',
                        progress_bg: '#E5E7EB',
                        icon_active: '#FF6B00',
                        icon_inactive: '#D1D5DB',
                        status_label: '#FF6B00'
                    },
                    visible_stages: [
                        'Aberto', 'Terceirizado', 'Analise Tecnica', 'Aprovacao', 'Compra Peca',
                        'Andamento Reparo', 'Teste Final', 'Retirada Cliente', 'Finalizado'
                    ]
                };
                this.notify("Configuração redefinida (Salvar para aplicar)");
            }
        },

        getStatusLabelForTracker(status) {
            if (this.trackerConfig.custom_labels && this.trackerConfig.custom_labels[status]) {
                return this.trackerConfig.custom_labels[status];
            }
            return this.getStatusLabel(status);
        },

        extractTime(timeStr) {
            if (!timeStr) return '';
            if (timeStr.includes('T')) {
                const d = new Date(timeStr);
                // Extract HH:mm safely from a valid date regardless of locale string behavior
                const h = String(d.getHours()).padStart(2, '0');
                const m = String(d.getMinutes()).padStart(2, '0');
                return `${h}:${m}`;
            }
            return timeStr.substring(0, 5);
        },

        toggleTrackerStage(stage) {
            const idx = this.trackerConfig.visible_stages.indexOf(stage);
            if (idx > -1) {
                // Don't remove if it's the last one or strict logic (e.g. keep 'Aberto'?)
                // Allow removing any for flexibility, but maybe warn if empty?
                this.trackerConfig.visible_stages.splice(idx, 1);
            } else {
                // Add back in correct order
                this.trackerConfig.visible_stages.push(stage);
                // Sort according to standard order
                this.trackerConfig.visible_stages.sort((a, b) => {
                    return (this.STATUS_INDEX_MAP[a] ?? -1) - (this.STATUS_INDEX_MAP[b] ?? -1);
                });
            }
        },

        // --- LOGGING ---
        async logTicketAction(ticketId, action, details = null) {
            return await window.AIDALogsNotificationsService.logTicketAction(ticketId, action, details, {
                state: this,
                supabaseFetch: (ep, method, payload, requestOptions) => this.supabaseFetch(ep, method, payload, requestOptions),
                fetchGlobalLogs: () => this.fetchGlobalLogs()
            });
        },

        getLogActorName(log) {
            const actorName = String(log?.user_name || '').trim();
            if (!actorName) return 'Sistema';
            if (actorName === 'Owner' || actorName === 'Admin') return 'Administrador';
            return actorName;
        },

        async fetchTicketLogs(ticketId) {
            return await window.AIDALogsNotificationsService.fetchTicketLogs(ticketId, {
                hasRole: (r) => this.hasRole(r),
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload)
            });
        },

        async fetchGlobalLogs() {
            if (this.globalLogsInFlight) return;
            this.globalLogsInFlight = true;
            try {
                return await window.AIDALogsNotificationsService.fetchGlobalLogs({
                    state: this,
                    supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload)
                });
            } finally {
                this.globalLogsInFlight = false;
            }
        },

        // --- NOTIFICATIONS ---
        async fetchNotifications() {
            if (this.notificationsInFlight) return;
            this.notificationsInFlight = true;
            try {
                return await window.AIDALogsNotificationsService.fetchNotifications({
                    state: this,
                    supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload)
                });
            } finally {
                this.notificationsInFlight = false;
            }
        },

        async createNotification(data) {
            return await window.AIDALogsNotificationsService.createNotification(data, {
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload)
            });
        },

        async markNotificationRead(id) {
            return await window.AIDALogsNotificationsService.markNotificationRead(id, {
                state: this,
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload)
            });
        },

        async markAllRead() {
            return await window.AIDALogsNotificationsService.markAllRead({
                state: this,
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload)
            });
        },

        async checkTimeBasedAlerts() {
            if (!this.tickets) return;

            const now = new Date();
            const oneHour = 60 * 60 * 1000;

            if (this.hasRole('admin')) {
                this.tickets.forEach(t => {
                    if (t.deadline && !['Finalizado', 'Retirada Cliente'].includes(t.status)) {
                        const deadline = new Date(t.deadline);
                        const diff = deadline - now;
                        if (diff > 0 && diff < oneHour) {
                            // Gargalo logic
                        }
                    }
                });
            }
        },

        async openLogs(ticket) {
            this.loading = true;
            try {
                this.ticketLogs = await this.fetchTicketLogs(ticket.id);
                this.logViewMode = 'timeline';
                this.modals.logs = true;
            } finally {
                this.loading = false;
            }
        },

        // --- 5. POLÍTICA DE REFRESH VIA REALTIME ---

        isRelevantUpdate(payload) {
            if (!payload) return false;
            const { eventType, new: newRec, old: oldRec } = payload;

            // 1. Workspace Security Check
            if (newRec && newRec.workspace_id && this.user && this.user.workspace_id) {
                if (newRec.workspace_id !== this.user.workspace_id) {
                    // console.log('[Dashboard][Realtime] ignored (wrong workspace)');
                    return false;
                }
            }

            // 2. Event Type Check
            if (eventType === 'INSERT' || eventType === 'DELETE') {
                return true;
            }

            // 3. Update Relevance Check
            if (eventType === 'UPDATE') {
                const fields = [
                    'status',
                    'delivered_at',
                    'repair_start_at',
                    'repair_end_at',
                    'budget_sent_at',
                    'pickup_available_at',
                    'technician_id',
                    'defect_reported', // Maps to 'defect' concept
                    'device_model',
                    'created_at',
                    'deleted_at'
                ];

                // Check value changes strictly
                for (const f of fields) {
                    const oldVal = oldRec ? oldRec[f] : undefined;
                    const newVal = newRec ? newRec[f] : undefined;
                    if (newVal != oldVal) return true;
                }
            }

            console.log('[Dashboard][Realtime] ignored (not relevant)');
            return false;
        },

        handleRealtimeUpdate(payload) {
            console.log('[RT] event', payload);

            // 1. Immediate update for focused ticket
            if (this.selectedTicket && payload.new && payload.new.id === this.selectedTicket.id) {
                this.selectedTicket = { ...this.selectedTicket, ...payload.new };
            }
            if (payload.new && payload.new.id === this.activeTicketId) {
                // Ensure state array stays fresh too
                const idx = this.tickets.findIndex(t => t.id === payload.new.id);
                if (idx > -1) {
                     this.tickets[idx] = { ...this.tickets[idx], ...payload.new };
                }
            }

            // 2. Optimized Dashboard Refresh (Throttle + Relevance Check)
            if (this.view === 'dashboard') {
                if (this.isRelevantUpdate(payload)) {
                    console.log('[Dashboard][Realtime] relevant event -> scheduling refresh');
                    this.invalidateDashboardCache('realtime_event');
                    this.requestDashboardMetrics({ reason: 'realtime' });
                }
            }

            // 3. In-Memory List Refresh Strategy (Avoid expensive fetchTickets calls)
            if (payload.eventType === 'INSERT' && payload.new) {
                // Prevent duplicates
                if (!this.tickets.some(t => t.id === payload.new.id)) {
                    // Only add to the beginning if we are on the first page or Kanban (no pagination limit visually yet)
                    if (this.ticketPagination.page === 0 || this.view === 'kanban') {
                        this.tickets.unshift(payload.new);
                    } else {
                        this.notify("Novos chamados disponíveis.", "info");
                    }
                }
            } else if (payload.eventType === 'UPDATE' && payload.new) {
                const idx = this.tickets.findIndex(t => t.id === payload.new.id);
                if (idx > -1) {
                    if (payload.new.deleted_at) {
                        this.tickets.splice(idx, 1); // Remove if logically deleted
                    } else {
                        this.tickets[idx] = { ...this.tickets[idx], ...payload.new }; // Update local state directly
                    }
                } else if (!payload.new.deleted_at && (this.ticketPagination.page === 0 || this.view === 'kanban')) {
                    // If it was updated but we didn't have it locally (e.g. moved into our filter view scope)
                    // we push it to ensure it appears. For perfect sorting, a fetch is ideal, but unshift is safe for RT.
                    this.tickets.unshift(payload.new);
                }
            }
        },

        handleSearchInput() {
            if (this.searchDebounceTimer) clearTimeout(this.searchDebounceTimer);
            this.searchDebounceTimer = setTimeout(() => {
                this.ticketPagination.page = 0; // Reset to first page
                // Synchronize search for operational filters based on view
                if (this.view === 'kanban') {
                    this.kanbanOperationalFilters.search = (this.searchQuery || '').trim();
                } else if (this.view === 'dashboard') {
                    this.homeOperationalFilters.search = (this.searchQuery || '').trim();
                }
                if (this.view === 'dashboard') {
                    this.fetchHomeOperationalQueue();
                } else {
                    this.fetchTickets();
                }
                if (this.view === 'dashboard' || this.view === 'admin_dashboard') {
                    this.requestDashboardMetrics({ reason: 'search' });
                }
            }, 500); // 500ms debounce
        },

        async loadMoreTickets() {
            if (!this.ticketPagination.hasMore || this.ticketPagination.isLoading) return;
            this.fetchTickets(true);
        },

        async loadMoreFinalized() {
            if (this.isLoadingFinalized || !this.finalizedHasMore) return;
            this.isLoadingFinalized = true;
            this.finalizedPage++;

            try {
                const data = await window.AIDATicketQueryService.fetchFinalizedTicketsData({
                    state: this,
                    supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload)
                });

                if (data) {
                    if (data.length < this.finalizedLimit) this.finalizedHasMore = false;
                    this.tickets = [...this.tickets, ...data];
                }
            } catch (e) {
                console.error("Load More Finalized Error:", e);
                this.finalizedPage--; // Revert page on error
            } finally {
                this.isLoadingFinalized = false;
            }
        },

        async fetchFornecedores() {
            return await window.AIDACatalogService.fetchFornecedores({
                state: this,
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload)
            });
        },

        openFornecedorModal(fornecedor = null) {
            if (fornecedor) {
                this.fornecedorForm = { ...fornecedor };
            } else {
                this.fornecedorForm = { id: null, razao_social: '', cnpj: '', fornece: '', whatsapp: '' };
            }
            this.modals.fornecedor = true;
        },

        async saveFornecedor() {
            return await window.AIDACatalogService.saveFornecedor({
                state: this,
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload),
                notify: (msg, type) => this.notify(msg, type),
                fetchFornecedores: () => this.fetchFornecedores(),
                setLoading: (val) => { this.loading = val; },
                closeModal: (name) => { this.modals[name] = false; }
            });
        },

        async deleteFornecedor(id) {
            return await window.AIDACatalogService.deleteFornecedor(id, {
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload),
                fetchFornecedores: () => this.fetchFornecedores()
            });
        },

        getBenchAppointmentDate(ticket) {
            if (!ticket) return null;
            if (ticket.status === 'Analise Tecnica') return this.isAppointmentTypeEnabled('analysis') ? (ticket.analysis_scheduled_at || null) : null;
            if (ticket.status === 'Andamento Reparo') return this.isAppointmentTypeEnabled('repair') ? (ticket.repair_scheduled_at || null) : null;
            return (this.isAppointmentTypeEnabled('repair') ? ticket.repair_scheduled_at : null)
                || (this.isAppointmentTypeEnabled('analysis') ? ticket.analysis_scheduled_at : null)
                || null;
        },

        getBenchDeadlineDate(ticket) {
            if (!ticket) return null;
            if (ticket.status === 'Analise Tecnica') {
                return (this.isFieldVisible('analysis_deadline') ? ticket.analysis_deadline : null)
                    || (this.isFieldVisible('deadline') ? ticket.deadline : null)
                    || null;
            }
            return (this.isFieldVisible('deadline') ? ticket.deadline : null)
                || (this.isFieldVisible('analysis_deadline') ? ticket.analysis_deadline : null)
                || null;
        },

        getValidTimestamp(value) {
            if (!value) return null;
            const timestamp = new Date(value).getTime();
            return Number.isFinite(timestamp) ? timestamp : null;
        },

        compareBenchTickets(a, b) {
            const requestedA = this.isPriorityRequestEnabled() && Boolean(a?.priority_requested);
            const requestedB = this.isPriorityRequestEnabled() && Boolean(b?.priority_requested);
            if (requestedA !== requestedB) return requestedA ? -1 : 1;

            // Use the next available date when a ticket has no appointment or deadline.
            const appointmentA = this.getValidTimestamp(this.getBenchAppointmentDate(a));
            const appointmentB = this.getValidTimestamp(this.getBenchAppointmentDate(b));
            const deadlineA = this.getValidTimestamp(this.getBenchDeadlineDate(a));
            const deadlineB = this.getValidTimestamp(this.getBenchDeadlineDate(b));
            const createdA = this.getValidTimestamp(a?.created_at) ?? Number.MAX_SAFE_INTEGER;
            const createdB = this.getValidTimestamp(b?.created_at) ?? Number.MAX_SAFE_INTEGER;
            const effectiveA = appointmentA ?? deadlineA ?? createdA;
            const effectiveB = appointmentB ?? deadlineB ?? createdB;

            if (effectiveA !== effectiveB) return effectiveA - effectiveB;

            // Deterministic tie-breakers preserve the requested hierarchy.
            const deadlineTieA = deadlineA ?? createdA;
            const deadlineTieB = deadlineB ?? createdB;
            if (deadlineTieA !== deadlineTieB) return deadlineTieA - deadlineTieB;
            if (createdA !== createdB) return createdA - createdB;

            return String(a?.os_number || '').localeCompare(String(b?.os_number || ''), undefined, { numeric: true });
        },

        sortBenchTickets(tickets) {
            return [...(tickets || [])].sort((a, b) => this.compareBenchTickets(a, b));
        },

        getVisibleBenchTickets(status, applySearch = false) {
            let visibleTickets = this.techTickets.filter(ticket => ticket.status === status);

            if (this.showTodayOnly) {
                const scheduleField = status === 'Analise Tecnica'
                    ? 'analysis_scheduled_at'
                    : (status === 'Andamento Reparo' ? 'repair_scheduled_at' : null);

                if (scheduleField) {
                    visibleTickets = visibleTickets.filter(ticket => {
                        const scheduledAt = ticket[scheduleField];
                        return scheduledAt && this.isSameDay(scheduledAt, new Date());
                    });
                }
            }

            if (applySearch) {
                visibleTickets = visibleTickets.filter(ticket => this.matchesSearch(ticket));
            }

            return visibleTickets;
        },

        async fetchTickets(loadMore = false) {
            if (!this.user?.workspace_id) return;

            // Guard: Prevent concurrent fetches (unless forced by loadMore)
            if (this.ticketPagination.isLoading) {
                console.log("[FetchTickets] Blocked by isLoading guard");
                return;
            }

            this.ticketPagination.isLoading = true;

            if (loadMore) {
                this.ticketPagination.page++;
            } else {
                this.ticketPagination.page = 0;
                this.ticketPagination.hasMore = true;
                // Preserve UI smoothly until response arrives if not paginating
            }

            try {
                const result = await window.AIDATicketQueryService.fetchTicketsData({
                    state: this,
                    supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload),
                    hasRole: (r) => this.hasRole(r)
                }, loadMore);

                // OPERATIONAL RPC MODE HANDLING
                if (result.mode === 'operational_rpc') {
                    this.kanbanOperationalCounts = result.counts;
                    this.kanbanOperationalLastResponse = result.data;

                    if (loadMore) {
                        this.tickets = [...this.tickets, ...result.data];
                    } else {
                        this.tickets = result.data;
                    }

                    if (result.data.length < this.ticketPagination.limit) {
                        this.ticketPagination.hasMore = false;
                    }
                    this.ticketPagination.isLoading = false;
                    return;
                }

                if (result.mode === 'kanban') {
                    if (this.showFinalized && result.finalizedHasMore !== null) {
                        this.finalizedHasMore = result.finalizedHasMore;
                    }
                    this.tickets = result.data;
                    this.ticketPagination.isLoading = false;
                    return;
                }

                const data = result.data;
                if (data) {
                    if (loadMore) {
                        this.tickets = [...this.tickets, ...data];
                    } else {
                        this.tickets = data;
                    }

                    if (data.length < this.ticketPagination.limit) {
                        this.ticketPagination.hasMore = false;
                    }

                    // POPULATE TECH TICKETS (Client Side Filter for safety/convenience)
                    if (this.view === 'tech_orders') {
                        this.techTickets = this.sortBenchTickets(this.tickets);
                    } else {
                        let relevantTickets = this.tickets;
                        const isTechOnly = !this.hasRole('admin') && this.hasRole('tecnico');
                        if (isTechOnly && this.user) {
                            relevantTickets = relevantTickets.filter(t => t.technician_id == this.user.id || t.technician_id == null);
                        }

                        relevantTickets = relevantTickets.filter(t => {
                            const allowedStatuses = ['Analise Tecnica', 'Andamento Reparo'];
                            if (this.getTestFlowMode() === 'technician') {
                                allowedStatuses.push('Teste Final');
                            }
                            return allowedStatuses.includes(t.status);
                        });
                        this.techTickets = this.sortBenchTickets(relevantTickets);
                    }
                }
            } catch (err) {
                 console.warn("Fetch exception:", err);
                 this.notify("Erro ao buscar chamados.", "error");
            } finally {
                 this.ticketPagination.isLoading = false;
            }
        },

        async fetchTemplates() {
            return await window.AIDACatalogService.fetchTemplates({
                state: this,
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload)
            });
        },

        // --- DEVICE MODELS ---
        async fetchDeviceModels() {
            return await window.AIDACatalogService.fetchDeviceModels({
                state: this,
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload)
            });
        },

        async fetchDefectOptions() {
            return await window.AIDACatalogService.fetchDefectOptions({
                state: this,
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload)
            });
        },

        async fetchOutsourcedCompanies() {
            return await window.AIDACatalogService.fetchOutsourcedCompanies({
                state: this,
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload)
            });
        },

        async createOutsourcedCompany(name, phone, services) {
            return await window.AIDACatalogService.createOutsourcedCompany(name, phone, services, {
                state: this,
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload),
                notify: (msg, type) => this.notify(msg, type),
                fetchOutsourcedCompanies: () => this.fetchOutsourcedCompanies()
            });
        },

        async deleteOutsourcedCompany(id) {
            return await window.AIDACatalogService.deleteOutsourcedCompany(id, {
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload),
                notify: (msg, type) => this.notify(msg, type),
                fetchOutsourcedCompanies: () => this.fetchOutsourcedCompanies()
            });
        },

        async createDeviceModel(name) {
            return await window.AIDACatalogService.createDeviceModel(name, {
                state: this,
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload),
                notify: (msg, type) => this.notify(msg, type),
                fetchDeviceModels: () => this.fetchDeviceModels()
            });
        },

        async createDefectOption(name) {
            return await window.AIDACatalogService.createDefectOption(name, {
                state: this,
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload),
                notify: (msg, type) => this.notify(msg, type),
                fetchDefectOptions: () => this.fetchDefectOptions()
            });
        },

        async deleteDeviceModel(id) {
            return await window.AIDACatalogService.deleteDeviceModel(id, {
                state: this,
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload),
                notify: (msg, type) => this.notify(msg, type),
                fetchDeviceModels: () => this.fetchDeviceModels()
            });
        },

        async deleteDefectOption(id) {
            return await window.AIDACatalogService.deleteDefectOption(id, {
                state: this,
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload),
                notify: (msg, type) => this.notify(msg, type),
                fetchDefectOptions: () => this.fetchDefectOptions()
            });
        },

        catalogSearchTerm() {
            return (this.catalogManagement.search || '').trim().toLowerCase();
        },

        filteredCatalogDeviceModels() {
            const search = this.catalogSearchTerm();
            return this.deviceModels.filter(model => !search || model.name.toLowerCase().includes(search));
        },

        filteredCatalogDefectOptions() {
            const search = this.catalogSearchTerm();
            return this.defectOptions.filter(option => !search || option.name.toLowerCase().includes(search));
        },

        catalogTemplateItems(template) {
            return Array.isArray(template?.items) ? template.items : [];
        },

        filteredCatalogChecklistTemplates() {
            const search = this.catalogSearchTerm();
            return this.checklistTemplates.filter(template => {
                const typeLabel = (template.type || 'entry') === 'final' ? 'saída' : 'entrada';
                const searchable = [
                    template.name,
                    typeLabel,
                    ...this.catalogTemplateItems(template)
                ].join(' ').toLowerCase();
                return !search || searchable.includes(search);
            });
        },

        filteredCatalogFornecedores() {
            const search = this.catalogSearchTerm();
            return this.fornecedores.filter(fornecedor => {
                const searchable = [
                    fornecedor.razao_social,
                    fornecedor.cnpj,
                    fornecedor.fornece,
                    fornecedor.whatsapp
                ].filter(Boolean).join(' ').toLowerCase();
                return !search || searchable.includes(search);
            });
        },

        async createManagedDeviceModel() {
            const created = await this.createDeviceModel(this.catalogManagement.modelName);
            if (created) this.catalogManagement.modelName = '';
        },

        startManagedDeviceModelEdit(model) {
            this.catalogManagement.editingModelId = model.id;
            this.catalogManagement.editingModelName = model.name;
            this.$nextTick(() => document.querySelector('[data-catalog-model-edit]')?.focus());
        },

        cancelManagedDeviceModelEdit() {
            this.catalogManagement.editingModelId = null;
            this.catalogManagement.editingModelName = '';
        },

        async saveManagedDeviceModel() {
            const updated = await window.AIDACatalogService.updateDeviceModel(
                this.catalogManagement.editingModelId,
                this.catalogManagement.editingModelName,
                {
                    state: this,
                    supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload),
                    notify: (msg, type) => this.notify(msg, type),
                    fetchDeviceModels: () => this.fetchDeviceModels()
                }
            );
            if (updated) this.cancelManagedDeviceModelEdit();
        },

        async createManagedDefectOption() {
            const created = await this.createDefectOption(this.catalogManagement.defectName);
            if (created) this.catalogManagement.defectName = '';
        },

        startManagedDefectEdit(option) {
            this.catalogManagement.editingDefectId = option.id;
            this.catalogManagement.editingDefectName = option.name;
            this.$nextTick(() => document.querySelector('[data-catalog-defect-edit]')?.focus());
        },

        cancelManagedDefectEdit() {
            this.catalogManagement.editingDefectId = null;
            this.catalogManagement.editingDefectName = '';
        },

        async saveManagedDefectOption() {
            const updated = await window.AIDACatalogService.updateDefectOption(
                this.catalogManagement.editingDefectId,
                this.catalogManagement.editingDefectName,
                {
                    state: this,
                    supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload),
                    notify: (msg, type) => this.notify(msg, type),
                    fetchDefectOptions: () => this.fetchDefectOptions()
                }
            );
            if (updated) this.cancelManagedDefectEdit();
        },

        openManagedChecklistEditor(template = null) {
            const isExisting = Boolean(template);
            this.catalogManagement.checklistEditorOpen = true;
            this.catalogManagement.checklistId = template?.id || null;
            this.catalogManagement.checklistName = template?.name || '';
            this.catalogManagement.checklistType = (template?.type || 'entry') === 'final' ? 'final' : 'entry';
            this.catalogManagement.checklistItems = isExisting ? [...this.catalogTemplateItems(template)] : [];
            this.catalogManagement.checklistItemDraft = '';
            this.$nextTick(() => document.querySelector('[data-catalog-checklist-name]')?.focus());
        },

        cancelManagedChecklistEditor() {
            this.catalogManagement.checklistEditorOpen = false;
            this.catalogManagement.checklistId = null;
            this.catalogManagement.checklistName = '';
            this.catalogManagement.checklistType = 'entry';
            this.catalogManagement.checklistItems = [];
            this.catalogManagement.checklistItemDraft = '';
        },

        addManagedChecklistItem() {
            const item = (this.catalogManagement.checklistItemDraft || '').trim();
            if (!item) return;
            if (this.catalogManagement.checklistItems.some(existing => existing.toLowerCase() === item.toLowerCase())) {
                this.notify("Esse item já está no checklist.", "error");
                return;
            }
            this.catalogManagement.checklistItems.push(item);
            this.catalogManagement.checklistItemDraft = '';
        },

        removeManagedChecklistItem(index) {
            this.catalogManagement.checklistItems.splice(index, 1);
        },

        async saveManagedChecklist() {
            const saved = await window.AIDACatalogService.saveManagedChecklist({
                id: this.catalogManagement.checklistId,
                name: this.catalogManagement.checklistName,
                type: this.catalogManagement.checklistType,
                items: this.catalogManagement.checklistItems
            }, {
                state: this,
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload),
                notify: (msg, type) => this.notify(msg, type),
                fetchTemplates: () => this.fetchTemplates()
            });
            if (saved) this.cancelManagedChecklistEditor();
        },

        async deleteManagedChecklist(template) {
            const deleted = await window.AIDACatalogService.deleteManagedChecklist(template, {
                state: this,
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload),
                notify: (msg, type) => this.notify(msg, type),
                fetchTemplates: () => this.fetchTemplates()
            });
            if (deleted && this.catalogManagement.checklistId === template.id) {
                this.cancelManagedChecklistEditor();
            }
        },

        openNewTicketModal() {
            this.closeSchedulePanel();
            this.schedulePanelMode = '';
            this.scheduleAvailabilityLoading = false;
            this.scheduleAvailabilityData = null;
            this.selectedAnalysisAppointment = null;
            this.selectedRepairAppointment = null;
            this.scheduleCurrentWeekStart = null;
            this.bypassAnalysisCheck = false;
            this.ticketForm = {
                id: crypto.randomUUID(),
                client_name: '', os_number: '', model: '', serial: '',
                defects: [], priority: 'Normal', contact: '',
                deadline: '', analysis_deadline: '', device_condition: '',
                technician_id: '',
                budget_approved: false, approved_route: 'repair', parts_needed: '',
                is_outsourced: false, outsourced_company_id: '',
                checklist: [], checklist_final: [], photos: [], notes: ''
            };
            this.ticketFormErrors = {};
            this.modals.ticket = true;
        },

        focusTicketFields(fields) {
            const fieldKeys = [...new Set((fields || []).filter(Boolean))];
            if (!fieldKeys.length) return;

            this.ticketFormErrors = fieldKeys.reduce((errors, field) => ({ ...errors, [field]: true }), {});

            setTimeout(() => {
                fieldKeys.forEach(field => this.applyTicketFieldError(field, true));

                const firstField = document.querySelector('[data-ticket-field="' + fieldKeys[0] + '"]');
                if (!firstField) return;

                firstField.scrollIntoView({ behavior: 'smooth', block: 'center' });
                const visibleControl = Array.from(firstField.querySelectorAll('input, select, textarea, button'))
                    .find(control => control.offsetParent !== null && !control.disabled);
                if (visibleControl) visibleControl.focus({ preventScroll: true });
            }, 50);
        },

        focusTicketField(field) {
            this.focusTicketFields([field]);
        },

        clearTicketFieldError(field) {
            if (!field || !this.ticketFormErrors?.[field]) return;
            this.ticketFormErrors = { ...this.ticketFormErrors, [field]: false };
            this.applyTicketFieldError(field, false);
        },

        applyTicketFieldError(field, active) {
            const fieldElement = document.querySelector('[data-ticket-field="' + field + '"]');
            if (!fieldElement) return;

            fieldElement.classList.toggle('bg-red-50', active);
            fieldElement.classList.toggle('rounded-lg', active);
            fieldElement.classList.toggle('border', active);
            fieldElement.classList.toggle('border-red-300', active);
            fieldElement.classList.toggle('p-1.5', active);

            Array.from(fieldElement.querySelectorAll('input, select, textarea, button')).forEach(control => {
                if (control.type === 'hidden' || control.closest('[data-ignore-ticket-validation]')) return;
                control.classList.toggle('border-red-500', active);
                control.classList.toggle('ring-2', active);
                control.classList.toggle('ring-red-100', active);
            });
        },

        handleBudgetApprovalEntryChange() {
            // A entrada aprovada não percorre a análise; evita criar uma agenda incompatível.
            if (this.ticketForm.budget_approved) {
                this.ticketForm.analysis_deadline = '';
                this.selectedAnalysisAppointment = null;
            } else {
                this.ticketForm.parts_needed = '';
                this.selectedRepairAppointment = null;
            }
        },

        handleApprovedRouteChange() {
            if (this.ticketForm.approved_route !== 'repair') {
                this.selectedRepairAppointment = null;
            }
        },

        addChecklistItem() {
            if (this.newChecklistItem.trim()) {
                this.ticketForm.checklist.push({ item: this.newChecklistItem, ok: false });
                this.newChecklistItem = '';
            }
        },
        removeChecklistItem(index) {
            this.ticketForm.checklist.splice(index, 1);
        },
        async saveTemplate() {
            return await window.AIDACatalogService.saveTemplate({
                state: this,
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload),
                notify: (msg, type) => this.notify(msg, type),
                fetchTemplates: () => this.fetchTemplates()
            });
        },

        async deleteTemplate() {
            return await window.AIDACatalogService.deleteTemplate({
                state: this,
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload),
                notify: (msg, type) => this.notify(msg, type),
                fetchTemplates: () => this.fetchTemplates()
            });
        },

        loadTemplate() {
            const tmpl = this.checklistTemplates.find(t => t.id === this.selectedTemplateId);
            if (tmpl) this.ticketForm.checklist = tmpl.items.map(s => ({ item: s, ok: false }));
        },

        // --- FINAL CHECKLIST HELPERS ---
        addChecklistFinalItem() {
            if (this.newChecklistFinalItem.trim()) {
                this.ticketForm.checklist_final.push({ item: this.newChecklistFinalItem, ok: false });
                this.newChecklistFinalItem = '';
            }
        },
        removeChecklistFinalItem(index) {
            this.ticketForm.checklist_final.splice(index, 1);
        },
        async saveTemplateFinal() {
            return await window.AIDACatalogService.saveTemplateFinal({
                state: this,
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload),
                notify: (msg, type) => this.notify(msg, type),
                fetchTemplates: () => this.fetchTemplates()
            });
        },

        async deleteTemplateFinal() {
            return await window.AIDACatalogService.deleteTemplateFinal({
                state: this,
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload),
                notify: (msg, type) => this.notify(msg, type),
                fetchTemplates: () => this.fetchTemplates()
            });
        },
        loadTemplateFinal() {
            const tmpl = this.checklistTemplates.find(t => t.id === this.selectedTemplateIdFinal);
            if (tmpl) this.ticketForm.checklist_final = tmpl.items.map(s => ({ item: s, ok: false }));
        },


        // ==========================================
        // SCHEDULING METHODS
        // ==========================================
        openSchedulePanel(mode, technicianId = null, ticket = null, afterSave = null) {
            if (!this.isAppointmentTypeEnabled(mode)) {
                return this.notify(`O agendamento de ${mode === 'repair' ? 'reparo' : 'análise'} está desativado no Gerenciamento.`, 'error');
            }
            const targetTicket = ticket || (this.modals.viewTicket ? this.selectedTicket : null);
            const targetTechId = technicianId || targetTicket?.technician_id || this.ticketForm.technician_id;

            if (!targetTechId || targetTechId === 'all') {
                return this.notify("O chamado precisa estar alocado a um técnico para agendar usando este atalho de calendário lateral. Tente alterar o técnico ou agendar via painel 'Gerenciamento de Agenda'.", "error");
            }
            this.schedulePanelMode = mode;
            this.schedulePanelTicket = targetTicket;
            this.schedulePanelTechnicianId = targetTechId;
            this.schedulePanelAfterSave = afterSave;
            this.scheduleCurrentWeekStart = new Date(); // Start with current week
            this.schedulePanelOpen = true;
            this.fetchScheduleAvailability(targetTechId);
        },

        closeSchedulePanel() {
            this.schedulePanelOpen = false;
            this.schedulePanelTicket = null;
            this.schedulePanelTechnicianId = null;
            this.schedulePanelAfterSave = null;
        },

        getTechnicianName(techId) {
            if (!techId || techId === 'all') return 'Nenhum técnico';
            const tech = this.getTechnicians().find(t => t.id === techId);
            return tech ? tech.name : 'Técnico Desconhecido';
        },

        async fetchScheduleAvailability(targetTechId = null) {
            const techId = targetTechId || this.schedulePanelTechnicianId || this.schedulePanelTicket?.technician_id || this.ticketForm.technician_id;
            if (!techId || techId === 'all') return;

            this.scheduleAvailabilityLoading = true;
            this.scheduleAvailabilityData = [];

            try {
                // Ensure date is properly formatted as YYYY-MM-DD local timezone
                const tzOffset = this.scheduleCurrentWeekStart.getTimezoneOffset() * 60000; // offset in milliseconds
                const localISOTime = (new Date(this.scheduleCurrentWeekStart - tzOffset)).toISOString().slice(0, -1);
                const refDate = localISOTime.split('T')[0];
                const response = await this.supabaseFetch('rpc/get_schedule_availability', 'POST', {
                    p_technician_id: techId,
                    p_mode: this.schedulePanelMode,
                    p_reference_date: refDate,
                    p_days: 7
                });

                if (response && response.days) {
                    this.scheduleAvailabilityData = response.days;
                } else if (response && Array.isArray(response)) {
                    // Fallback in case the RPC returns an array directly instead of an object with 'days'
                    this.scheduleAvailabilityData = response;
                }
            } catch (error) {
                console.error("Error fetching schedule:", error);
                this.notify("Erro ao buscar disponibilidade.", "error");
            } finally {
                this.scheduleAvailabilityLoading = false;
            }
        },

        navigateScheduleWeek(direction) {
            if (!this.scheduleCurrentWeekStart) this.scheduleCurrentWeekStart = new Date();
            const date = new Date(this.scheduleCurrentWeekStart);
            date.setDate(date.getDate() + (direction * 7));
            this.scheduleCurrentWeekStart = date;
            this.fetchScheduleAvailability();
        },

        formatScheduleWeekRange() {
            if (!this.scheduleCurrentWeekStart) return '';
            const start = new Date(this.scheduleCurrentWeekStart);
            const end = new Date(this.scheduleCurrentWeekStart);
            end.setDate(end.getDate() + 6);

            const format = (d) => d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' });
            return `${format(start)} - ${format(end)}`;
        },

        formatScheduleDate(dateStr) {
            if (!dateStr) return '';
            const d = new Date(dateStr + 'T12:00:00'); // Prevent timezone shift
            const weekDay = d.toLocaleDateString('pt-BR', { weekday: 'short' }).replace('.', '');
            const dayMonth = d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' });
            return `${weekDay}, ${dayMonth}`;
        },

        formatDateLocal(isoStr) {
            if (!isoStr) return '';
            const d = new Date(isoStr);
            if (isNaN(d.getTime())) return '';

            const dayMonth = d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' });
            const time = d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });

            return `${dayMonth}, ${time}`;
        },

        formatTimeOnly(timeStr) {
            if (!timeStr) return '';
            // Handle cases where time might be full ISO or just HH:mm:ss
            if (timeStr.includes('T')) {
                const d = new Date(timeStr);
                return d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
            }
            // For simple strings like '14:00:00'
            const parts = timeStr.split(':');
            return `${parts[0]}:${parts[1]}`;
        },

        async selectScheduleSlot(dateStr, slot) {
            const targetTicket = this.schedulePanelTicket || (this.modals.viewTicket ? this.selectedTicket : null);
            const techId = this.schedulePanelTechnicianId || targetTicket?.technician_id || this.ticketForm.technician_id;
            const afterSave = this.schedulePanelAfterSave;

            const appointmentData = {
                date: dateStr,
                start: this.extractTime(slot.start),
                end: this.extractTime(slot.end),
                status: slot.status,
                technician_id: techId
            };

            if (targetTicket) {
                // Para uma OS existente, o contexto do painel define o chamado mesmo
                // quando ele foi aberto diretamente por um card do Kanban.
                this.loading = true;
                try {
                    const startStr = this.toUTC(`${dateStr}T${appointmentData.start}`);
                    const endStr = this.toUTC(`${dateStr}T${appointmentData.end}`);

                    await this.supabaseFetch('rpc/create_ticket_appointment', 'POST', {
                        p_ticket_id: targetTicket.id,
                        p_technician_id: techId,
                        p_appointment_type: this.schedulePanelMode,
                        p_scheduled_start: startStr,
                        p_scheduled_end: endStr,
                        p_notes: 'Agendado pelo painel lateral'
                    });

                    targetTicket[`${this.schedulePanelMode}_scheduled`] = true;
                    targetTicket[`${this.schedulePanelMode}_scheduled_at`] = startStr;
                    if (this.selectedTicket?.id === targetTicket.id) {
                        this.selectedTicket = { ...this.selectedTicket, ...targetTicket };
                        this.fetchTicketAppointments(targetTicket.id);
                    }

                    if (afterSave === 'approveRepair') {
                        const advanced = await window.AIDATicketActions.completeBudgetApproval(
                            targetTicket,
                            this._getActionDeps()
                        );
                        if (!advanced) {
                            this.notify("O reparo foi agendado, mas não foi possível avançar a etapa. Tente aprovar novamente.", "error");
                            this.closeSchedulePanel();
                            return;
                        }
                        this.notify("Reparo agendado e chamado enviado para reparo.");
                    } else {
                        this.notify("Agendamento criado com sucesso!");
                        this.fetchTickets();
                    }
                } catch (e) {
                    console.error("Erro ao salvar agendamento:", e);
                    this.notify("Falha ao salvar agendamento.", "error");
                } finally {
                    this.loading = false;
                }
            } else {
                // Em modo de Criação de Ticket, apenas guarda no buffer
                if (this.schedulePanelMode === 'analysis') {
                    this.selectedAnalysisAppointment = appointmentData;
                } else if (this.schedulePanelMode === 'repair') {
                    this.selectedRepairAppointment = appointmentData;
                }
            }

            this.closeSchedulePanel();
        },

        isSlotSelected(dateStr, slot) {
            const current = this.schedulePanelMode === 'analysis' ? this.selectedAnalysisAppointment : this.selectedRepairAppointment;
            if (!current) return false;
            return current.date === dateStr && current.start === this.extractTime(slot.start);
        },

        removeAppointment(mode) {
            if (mode === 'analysis') {
                this.selectedAnalysisAppointment = null;
            } else if (mode === 'repair') {
                this.selectedRepairAppointment = null;
            }
        },

        // ==========================================
        // SCHEDULE MANAGEMENT VIEW METHODS (Admin)
        // ==========================================
        async loadScheduleManagement() {
            this.scheduleManagement.loading = true;
            this.scheduleManagement.gridTechnicianId = this.scheduleManagement.selectedTechnicianId;

            const tasks = [];

            // 1. Unscheduled tickets should always load
            tasks.push(this.fetchUnscheduledTickets());

            // 2. Manager schedule only loads if a tech is selected
            if (this.scheduleManagement.gridTechnicianId) {
                this.scheduleManagement.data = [];
                this.scheduleManagement.capacitySummary = { booked: 0, total: 0 };
                tasks.push(this.fetchManagerSchedule());
            } else {
                this.scheduleManagement.data = null;
                this.scheduleManagement.capacitySummary = null;
            }

            await Promise.all(tasks);

            this.scheduleManagement.loading = false;
        },

        previewTechnicianSchedule(ticket) {
            if (ticket.technician_id) {
                this.scheduleManagement.gridTechnicianId = ticket.technician_id;
                this.fetchManagerSchedule();
            }
        },

        async fetchManagerSchedule() {
            try {
                const refDate = new Date(this.scheduleManagement.referenceDate);
                const tzOffset = refDate.getTimezoneOffset() * 60000;
                const localDateStr = (new Date(refDate.getTime() - tzOffset)).toISOString().split('T')[0];

                const response = await this.supabaseFetch('rpc/get_schedule_dashboard', 'POST', {
                    p_technician_id: this.scheduleManagement.gridTechnicianId,
                    p_view: this.scheduleManagement.viewMode,
                    p_reference_date: localDateStr
                });

                if (response && response.schedule) {
                    // A nova RPC retorna obj schedule contendo os appointments agrupados
                    // O frontend precisa remontar a visão estruturada (dias e slots) baseada nisso
                    // Ou utilizar os dados vindos direto de get_schedule_availability (se compatível)

                    // Como a RPC original (get_schedule_availability) estrutura dias e slots perfeitamente,
                    // precisamos chamar a RPC de availability se a dashboard não nos der `days`.
                    const availResponse = await this.supabaseFetch('rpc/get_schedule_availability', 'POST', {
                        p_technician_id: this.scheduleManagement.gridTechnicianId,
                        p_mode: 'all',
                        p_reference_date: localDateStr,
                        p_days: this.scheduleManagement.viewMode === 'day' ? 1 : 7
                    });

                    if (availResponse && availResponse.days) {
                        // Mesclar os appointments do backend (response.schedule.appointments) nos dias
                        const apps = response.schedule.appointments || [];
                        const blocks = response.schedule.blocks || [];

                        availResponse.days.forEach(day => {
                            if (day.slots) {
                                day.slots.forEach(slot => {
                                    slot.appointments = [];
                                    const slotStart = new Date(slot.start).getTime();

                                    apps.forEach(app => {
                                        const appStart = new Date(app.scheduled_start).getTime();
                                        if (appStart === slotStart) {
                                            if (this.scheduleManagement.typeFilter === 'all' || app.appointment_type === this.scheduleManagement.typeFilter) {
                                                slot.appointments.push({
                                                    id: app.id,
                                                    ticket_id: app.ticket_id,
                                                    technician_id: this.scheduleManagement.gridTechnicianId,
                                                    type: app.appointment_type,
                                                    start: app.scheduled_start,
                                                    end: app.scheduled_end,
                                                    status: app.status,
                                                    notes: app.notes,
                                                    os_number: app.os_number,
                                                    client_name: app.client_name,
                                                    device_model: app.device_model,
                                                    defect_reported: app.defect_reported,
                                                    analysis_deadline: app.analysis_deadline,
                                                    deadline: app.deadline
                                                });
                                            }
                                        }
                                    });
                                });
                            }
                        });
                        this.scheduleManagement.data = availResponse.days;

                        // Fake a basic capacity summary until backend gives `capacity_summary` properly
                        this.scheduleManagement.capacitySummary = {
                            total: response.schedule.counts?.total_appointments || 0,
                            booked: response.schedule.counts?.total_appointments || 0,
                            blocked: response.schedule.counts?.total_blocks || 0,
                            overbooked: 0
                        };
                    } else {
                        this.scheduleManagement.data = [];
                    }
                } else {
                    this.scheduleManagement.data = [];
                }
            } catch (error) {
                console.error("Error fetching manager schedule:", error);
                this.notify("Erro ao carregar a agenda.", "error");
            }
        },

        async fetchUnscheduledTickets() {
            this.scheduleManagement.unscheduledLoading = true;
            this.scheduleManagement.unscheduledItems = [];
            this.scheduleManagement.unscheduledTotal = 0;
            this.scheduleManagement.withoutTechnicianItems = [];
            this.scheduleManagement.withoutTechnicianTotal = 0;

            this.scheduleManagement.conflictItems = [];
            this.scheduleManagement.conflictTotal = 0;
            this.scheduleManagement.lateWithoutScheduleItems = [];
            this.scheduleManagement.lateWithoutScheduleTotal = 0;

            try {
                const filterTechId = this.scheduleManagement.selectedTechnicianId;

                // Sempre puxamos a lista geral de não agendados enviando null
                // porque queremos que a lateral se comporte como se não houvesse filtro caso techId = ''
                const response = await this.supabaseFetch('rpc/get_unscheduled_tickets', 'POST', {
                    p_technician_id: null,
                    p_appointment_type: this.scheduleManagement.typeFilter === 'all' ? null : this.scheduleManagement.typeFilter,
                    p_status: null,
                    p_limit: 500,
                    p_offset: 0
                });

                let allItems = [];
                if (response && typeof response === 'object' && response.items) {
                    allItems = response.items;
                }

                // O usuário pediu: se não tem técnico selecionado, aparece todos os cards (de todos os técnicos)
                // Se TEM técnico selecionado no select lá em cima, filtramos a lateral SOMENTE para aquele técnico e os SEM TÉCNICO.
                let filteredItems = allItems;
                if (filterTechId) {
                    filteredItems = allItems.filter(t => !t.technician_id || t.technician_id === filterTechId);
                }

                // Sem Técnico Block
                const purelyUnassigned = filteredItems.filter(t => !t.technician_id);
                this.scheduleManagement.withoutTechnicianItems = purelyUnassigned;
                this.scheduleManagement.withoutTechnicianTotal = purelyUnassigned.length;

                // Com Técnico (Não Agendados)
                const assignedUnscheduled = filteredItems.filter(t => t.technician_id);
                this.scheduleManagement.unscheduledItems = assignedUnscheduled;
                this.scheduleManagement.unscheduledTotal = assignedUnscheduled.length;

                const now = new Date();
                const uniqueItems = filteredItems;

                const lateItems = uniqueItems.filter(t => {
                    const deadlineToCheck = t.status === 'Analise Tecnica' ? t.analysis_deadline : t.deadline;
                    if (!deadlineToCheck) return false;
                    const d = new Date(deadlineToCheck);
                    return d < now;
                });

                this.scheduleManagement.lateWithoutScheduleItems = lateItems;
                this.scheduleManagement.lateWithoutScheduleTotal = lateItems.length;

                // 4. Conflict Items (Derived conservative visual proxy)
                // A reasonable visual proxy for "conflict" in the unscheduled list is tickets that are assigned
                // but whose deadline is extremely close (e.g. today or earlier) while there is NO available capacity today.
                // We analyze the loaded schedule capacity to derive this warning list.
                const conflicts = [];

                // Only evaluate if we have a technician and capacity loaded for the current view
                if (filterTechId && this.scheduleManagement.capacitySummary && (this.scheduleManagement.capacitySummary.booked >= this.scheduleManagement.capacitySummary.total)) {
                    const viewDateLimit = new Date(this.scheduleManagement.referenceDate);
                    viewDateLimit.setHours(23, 59, 59, 999);

                    for (const item of uniqueItems) {
                        // Skip if it's not assigned to the completely booked technician
                        if (item.technician_id !== filterTechId) continue;

                        const deadlineToCheck = item.status === 'Analise Tecnica' ? item.analysis_deadline : item.deadline;
                        if (!deadlineToCheck) continue;

                        const itemDeadline = new Date(deadlineToCheck);
                        // If the deadline is before the end of the loaded (booked) view and it's not scheduled, it's a conflict
                        if (itemDeadline <= viewDateLimit) {
                            conflicts.push(item);
                        }
                    }
                }

                // Deduplicate from late items to prevent noise (ticket can only be in one visual group logic here ideally, but arrays are separate)
                // Let's keep them purely in conflict if capacity is full, but user might just want the list
                this.scheduleManagement.conflictItems = conflicts;
                this.scheduleManagement.conflictTotal = conflicts.length;

            } catch (error) {
                console.error("Error fetching unscheduled tickets:", error);
            } finally {
                this.scheduleManagement.unscheduledLoading = false;
            }
        },

        navigateScheduleManagement(direction) {
            const date = new Date(this.scheduleManagement.referenceDate);
            const daysToMove = this.scheduleManagement.viewMode === 'day' ? direction * 1 : direction * 7;
            date.setDate(date.getDate() + daysToMove);
            this.scheduleManagement.referenceDate = date.toLocaleDateString('en-CA'); // YYYY-MM-DD
            this.loadScheduleManagement();
        },


        openAppointmentActionMenu(appointment, dateStr, slot) {
            // Use the correct editingAppointment shape
            this.scheduleManagement.editingAppointment = this.getDefaultScheduleEditingAppointment();

            const ea = this.scheduleManagement.editingAppointment;
            ea.original = appointment;
            ea.ticket_id = appointment.ticket_id;
            ea.type = appointment.type;
            ea.new_date = dateStr;
            ea.new_start = this.extractTime(slot.start_time);
            ea.new_end = this.extractTime(slot.end_time);
            ea.new_technician_id = this.scheduleManagement.selectedTechnicianId;

            this.modals.rescheduleAppointment = true;
        },

        handleManagerSlotClick(dateStr, slot, event) {
            if (slot.status === 'livre') {
                const rect = event.currentTarget.getBoundingClientRect();
                this.scheduleManagement.slotActionPopover = {
                    open: true,
                    date: dateStr,
                    slot: slot,
                    x: rect.right + window.scrollX + 10, // Position to the right of the slot
                    y: rect.top + window.scrollY
                };
            }
        },

        closeSlotPopover() {
            this.scheduleManagement.slotActionPopover.open = false;
        },

        openScheduleModalFromSidebar(ticket) {
            const type = ticket.status === 'Analise Tecnica' ? 'analysis' : 'repair';
            // Abre o modal de agendamento em modo criação passando o ticket, tipo inferido, e sem slot pré-definido
            this.openRescheduleModal(ticket.id, type, null, null);
        },

        initiateSidebarAction(ticket, action) {
            if (action === 'reschedule') {
                this.openScheduleModalFromSidebar(ticket);
            }
        },

        initiateSlotAction(actionType) {
            const dateStr = this.scheduleManagement.slotActionPopover.date;
            const slot = this.scheduleManagement.slotActionPopover.slot;
            this.closeSlotPopover();

            if (actionType === 'analysis' || actionType === 'repair') {
                // Open reschedule modal in "creation" mode without ticket
                this.openRescheduleModal('', actionType, null, {
                    date: dateStr,
                    start: this.extractTime(slot.start),
                    end: this.extractTime(slot.end)
                });
            } else if (actionType === 'block') {
                this.openBlockModal(dateStr, slot);
            }
        },

        openRescheduleModal(ticketId, type, appointmentObj, prefillSlot = null) {
            // Find ticket context from unscheduled lists if available to populate headers nicely during creation
            let ctx = null;
            if (ticketId && !appointmentObj) {
                // Sempre dar prioridade ao selectedTicket se houver um modal de OS aberto,
                // pois ele contém a carga de dados mais rica de Kanban (prazos, cliente, etc).
                if (this.selectedTicket && this.selectedTicket.id === ticketId) {
                    ctx = this.selectedTicket;
                } else {
                    // Fallback para as listas globais da lateral
                    const allUnscheduled = [
                        ...this.scheduleManagement.unscheduledItems,
                        ...this.scheduleManagement.withoutTechnicianItems,
                        ...this.scheduleManagement.lateWithoutScheduleItems,
                        ...this.scheduleManagement.conflictItems
                    ];
                    ctx = allUnscheduled.find(t => t.id === ticketId);
                }

                // Em último caso, se a gente clicou pela tela de Bancada onde não abriu o ticket details, busca na array global do Kanban
                if (!ctx && this.tickets) {
                    ctx = this.tickets.find(t => t.id === ticketId);
                }
            }

            this.scheduleManagement.editingAppointment = this.getDefaultScheduleEditingAppointment();
            const ea = this.scheduleManagement.editingAppointment;

            ea.ticket_id = ticketId;
            ea.type = type;
            ea.original = appointmentObj;
            ea.ticketContext = ctx;
            ea.new_date = prefillSlot ? prefillSlot.date : (appointmentObj ? appointmentObj.date : '');
            ea.new_start = prefillSlot ? prefillSlot.start : (appointmentObj ? appointmentObj.start : '');
            ea.new_end = prefillSlot ? prefillSlot.end : (appointmentObj ? appointmentObj.end : '');

            // Set technician intelligently based on available context
            let techId = appointmentObj ? appointmentObj.technician_id : this.scheduleManagement.selectedTechnicianId;
            if (!techId && ctx && ctx.technician_id) {
                techId = ctx.technician_id; // Puxa do contexto do ticket se houver técnico associado lá e não na aba lateral global
            }
            ea.new_technician_id = techId;

            this.modals.rescheduleAppointment = true;
        },

        closeRescheduleModal() {
            this.modals.rescheduleAppointment = false;
            this.scheduleManagement.editingAppointment = this.getDefaultScheduleEditingAppointment();
        },

        openBlockModal(dateStr, slot) {
            this.scheduleManagement.editingBlock = this.getDefaultScheduleEditingBlock();
            const eb = this.scheduleManagement.editingBlock;

            eb.block_id = slot?.block_id || null;
            eb.date = dateStr || new Date().toLocaleDateString('en-CA');
            if (slot) {
                eb.start = this.extractTime(slot.start_time || slot.start);
                eb.end = this.extractTime(slot.end_time || slot.end);
                eb.notes = slot.block_notes || '';
            } else {
                eb.start = '09:00';
                eb.end = '18:00';
            }

            this.modals.scheduleBlock = true;
        },

        closeBlockModal() {
            this.modals.scheduleBlock = false;
            this.scheduleManagement.editingBlock = this.getDefaultScheduleEditingBlock();
        },

        // --- Tech Schedule Configuration ---

        openTechConfigModal() {
            this.scheduleManagement.techConfig.technician_id = this.scheduleManagement.selectedTechnicianId || '';
            if (this.scheduleManagement.techConfig.technician_id) {
                this.loadTechConfig();
            }
            this.modals.techScheduleSettings = true;
        },

        addExtraBreak() {
            if (!this.scheduleManagement.techConfig.extraBreaks) {
                this.scheduleManagement.techConfig.extraBreaks = [];
            }

            // Generate today's date in YYYY-MM-DD format
            const today = new Date();
            const yyyy = today.getFullYear();
            const mm = String(today.getMonth() + 1).padStart(2, '0');
            const dd = String(today.getDate()).padStart(2, '0');
            const formattedToday = `${yyyy}-${mm}-${dd}`;

            this.scheduleManagement.techConfig.extraBreaks.push({
                active: true,
                name: 'Novo Intervalo',
                start: '15:00',
                end: '15:30',
                recurrence_type: 'none',
                specific_date: formattedToday,
                recurrence_days: []
            });
        },

        removeExtraBreak(index) {
            this.scheduleManagement.techConfig.extraBreaks.splice(index, 1);
        },

        closeTechConfigModal() {
            this.modals.techScheduleSettings = false;
        },

        async loadTechConfig() {
            const techId = this.scheduleManagement.techConfig.technician_id;
            if (!techId) return;

            this.loading = true;
            try {
                // Fetch from `technician_schedule_settings`.
                // Use maybeSingle() to avoid 406 Not Acceptable error when the technician has no custom setting yet
                const { data, error } = await supabaseClient
                    .from('technician_schedule_settings')
                    .select('*')
                    .eq('technician_id', techId)
                    .maybeSingle();

                if (error && error.code !== 'PGRST116') {
                    console.error("Error fetching tech config:", error);
                }

                if (data && data.settings) {
                    const s = data.settings;
                    this.scheduleManagement.techConfig = {
                        technician_id: techId,
                        workDays: s.workDays || this.scheduleManagement.techConfig.workDays,
                        hasBreak: s.hasBreak !== undefined ? s.hasBreak : true,
                        breakStart: s.breakStart || '12:00',
                        breakEnd: s.breakEnd || '13:00',
                        extraBreaks: s.extraBreaks || [],
                        slotDuration: s.slotDuration || 30,
                        maxConcurrent: s.maxConcurrent || 1
                    };
                }
            } catch (e) {
                console.warn("Could not load tech config (maybe none exists yet):", e);
            } finally {
                this.loading = false;
            }
        },

        async saveTechConfig() {
            const techId = this.scheduleManagement.techConfig.technician_id;
            if (!techId) return this.notify("Técnico inválido.", "error");

            this.loading = true;
            try {
                const payload = {
                    workDays: this.scheduleManagement.techConfig.workDays,
                    hasBreak: this.scheduleManagement.techConfig.hasBreak,
                    breakStart: this.scheduleManagement.techConfig.breakStart,
                    breakEnd: this.scheduleManagement.techConfig.breakEnd,
                    extraBreaks: this.scheduleManagement.techConfig.extraBreaks || [],
                    slotDuration: this.scheduleManagement.techConfig.slotDuration,
                    maxConcurrent: this.scheduleManagement.techConfig.maxConcurrent
                };

                // Upsert logic for technician_schedule_settings
                const { error } = await supabaseClient
                    .from('technician_schedule_settings')
                    .upsert({
                        technician_id: techId,
                        workspace_id: this.user.workspace_id,
                        settings: payload
                    }, { onConflict: 'technician_id' });

                if (error) throw error;

                this.notify("Configuração de agenda salva com sucesso!");
                this.closeTechConfigModal();
                if (this.scheduleManagement.selectedTechnicianId === techId) {
                    this.loadScheduleManagement(); // Refresh the grid to show new availability
                }
            } catch (e) {
                console.error("Error saving tech config:", e);
                this.notify("Erro ao salvar a configuração.", "error");
            } finally {
                this.loading = false;
            }
        },

        // --- Management Mutations ---

        async submitReschedule() {
            const ea = this.scheduleManagement.editingAppointment;
            const ticketIdToRefresh = ea.ticket_id || (ea.original ? ea.original.ticket_id : null);

            if (!this.isAppointmentTypeEnabled(ea.type)) {
                return this.notify(`O agendamento de ${ea.type === 'repair' ? 'reparo' : 'análise'} está desativado.`, 'error');
            }

            // Explicit guard against submitting a creation without selecting a ticket
            if (!ea.ticket_id && (!ea.original || !ea.original.id)) {
                return this.notify("Selecione um chamado pendente para agendar.", "error");
            }

            if (!ea.new_date || !ea.new_start || !ea.new_technician_id) {
                return this.notify("Selecione data, técnico e um horário livre disponível.", "error");
            }

            // --- REPAIR DEADLINE CHECK ---
            if (ea.type === 'repair' && !this.bypassRepairCheck) {
                // Try to find the ticket deadline
                let ticketDeadline = null;
                const ticketId = ea.ticket_id || (ea.original ? ea.original.ticket_id : null);

                if (ticketId) {
                    // Search in main tickets list
                    let ticket = this.tickets.find(t => t.id === ticketId);
                    // Search in schedule management unscheduled items if not found
                    if (!ticket && this.scheduleManagement.unscheduledItems) {
                        ticket = this.scheduleManagement.unscheduledItems.find(t => t.id === ticketId);
                    }
                    if (!ticket && this.scheduleManagement.conflictItems) {
                        ticket = this.scheduleManagement.conflictItems.find(t => t.id === ticketId);
                    }
                    if (!ticket && this.scheduleManagement.lateWithoutScheduleItems) {
                        ticket = this.scheduleManagement.lateWithoutScheduleItems.find(t => t.id === ticketId);
                    }
                    if (!ticket && this.scheduleManagement.withoutTechnicianItems) {
                        ticket = this.scheduleManagement.withoutTechnicianItems.find(t => t.id === ticketId);
                    }
                    // Search in selectedTicket (e.g., if viewing the ticket directly)
                    if (!ticket && this.selectedTicket && this.selectedTicket.id === ticketId) {
                        ticket = this.selectedTicket;
                    }

                    if (ticket && ticket.deadline) {
                        ticketDeadline = new Date(ticket.deadline);
                    }
                }

                if (ticketDeadline) {
                    // Determine end time
                    let localEndStr;
                    if (ea.new_end) {
                        localEndStr = `${ea.new_date}T${ea.new_end}`;
                    } else {
                        const startDate = new Date(`${ea.new_date}T${ea.new_start}`);
                        startDate.setHours(startDate.getHours() + 1);
                        const pad = (n) => n < 10 ? '0' + n : n;
                        localEndStr = `${startDate.getFullYear()}-${pad(startDate.getMonth() + 1)}-${pad(startDate.getDate())}T${pad(startDate.getHours())}:${pad(startDate.getMinutes())}`;
                    }

                    const appendDate = new Date(localEndStr);

                    if (appendDate > ticketDeadline) {
                        this.modals.confirmScheduleRepair = true;
                        return; // Stop execution, wait for user confirmation
                    }
                }
            }
            // --- END REPAIR DEADLINE CHECK ---

            this.loading = true;
            try {
                // If it already has an ID, we're rescheduling.
                // If not, it's a new appointment from the unscheduled list.
                const startStr = this.toUTC(`${ea.new_date}T${ea.new_start}`);

                // Em modo remarcação com busca de slots reais, ea.new_end já deve estar populado.
                // Se não estiver, fazemos fallback de 1 hora.
                let endStr;
                if (ea.new_end) {
                    endStr = this.toUTC(`${ea.new_date}T${ea.new_end}`);
                } else {
                    const startDate = new Date(`${ea.new_date}T${ea.new_start}`);
                    startDate.setHours(startDate.getHours() + 1);
                    const pad = (n) => n < 10 ? '0' + n : n;
                    const localEndStr = `${startDate.getFullYear()}-${pad(startDate.getMonth() + 1)}-${pad(startDate.getDate())}T${pad(startDate.getHours())}:${pad(startDate.getMinutes())}`;
                    endStr = this.toUTC(localEndStr);
                }

                if (ea.original && ea.original.id) {
                    await this.supabaseFetch('rpc/reschedule_ticket_appointment', 'POST', {
                        p_appointment_id: ea.original.id,
                        p_technician_id: ea.new_technician_id,
                        p_scheduled_start: startStr,
                        p_scheduled_end: endStr,
                        p_notes: 'Remarcado via Gestão'
                    });
                    this.notify("Agendamento remarcado com sucesso!");
                } else {
                    await this.supabaseFetch('rpc/create_ticket_appointment', 'POST', {
                        p_ticket_id: ea.ticket_id,
                        p_technician_id: ea.new_technician_id,
                        p_appointment_type: ea.type,
                        p_scheduled_start: startStr,
                        p_scheduled_end: endStr,
                        p_notes: 'Agendado via Gestão'
                    });
                    this.notify("Agendamento criado com sucesso!");
                }

                this.closeRescheduleModal();
                await this.loadScheduleManagement();

                // Recarrega a OS somente depois que agenda e gatilho terminaram.
                // Isso mantém cards, Minha Bancada e modal na mesma versão do servidor.
                await this.fetchTickets();
                await this.fetchGlobalLogs();

                if (ticketIdToRefresh) {
                    const refreshedTicket = this.tickets.find(t => t.id === ticketIdToRefresh);
                    if (refreshedTicket && this.selectedTicket?.id === ticketIdToRefresh) {
                        this.selectedTicket = refreshedTicket;
                    }
                    if (this.modals.viewTicket) {
                        await this.fetchTicketAppointments(ticketIdToRefresh);
                    }
                    if (this.modals.logs) {
                        this.ticketLogs = await this.fetchTicketLogs(ticketIdToRefresh);
                    }
                }

            } catch (e) {
                console.error(e);
                this.notify("Erro ao gerenciar agendamento.", "error");
            } finally {
                this.loading = false;
                this.bypassRepairCheck = false;
            }
        },

        async cancelAppointment() {
            const ea = this.scheduleManagement.editingAppointment;
            if (!ea || !ea.original || !ea.original.id) return;

            const ticketIdToRefresh = ea.ticket_id || ea.original.ticket_id;

            if (!confirm("Tem certeza que deseja cancelar este agendamento?")) return;

            this.loading = true;
            try {
                await this.supabaseFetch('rpc/cancel_ticket_appointment', 'POST', {
                    p_appointment_id: ea.original.id,
                    p_reason: 'Cancelado pelo Gestor'
                });
                this.notify("Agendamento cancelado.");
                this.closeRescheduleModal();
                this.loadScheduleManagement();
                await this.fetchTickets();
                await this.fetchGlobalLogs();
                if (ticketIdToRefresh && this.modals.logs) {
                    this.ticketLogs = await this.fetchTicketLogs(ticketIdToRefresh);
                }
            } catch (e) {
                console.error(e);
                this.notify("Erro ao cancelar.", "error");
            } finally {
                this.loading = false;
            }
        },

        async submitBlock() {
            const eb = this.scheduleManagement.editingBlock;
            if (!eb.date) return this.notify("Informe a data do bloqueio.", "error");

            this.loading = true;
            try {
                let startStr, endStr;
                let blockType = eb.full_day ? 'full_day' : 'time_range';

                if (eb.full_day) {
                    startStr = this.toUTC(`${eb.date}T00:00:00`);
                    endStr = this.toUTC(`${eb.date}T23:59:59`);
                } else {
                    if (!eb.start || !eb.end) {
                        this.loading = false;
                        return this.notify("Informe o horário de início e fim do bloqueio.", "error");
                    }
                    startStr = this.toUTC(`${eb.date}T${eb.start}`);
                    endStr = this.toUTC(`${eb.date}T${eb.end}`);
                }

                let recurrenceEndDateStr = null;
                if (eb.is_recurring && eb.recurrence_end_date) {
                    recurrenceEndDateStr = this.toUTC(`${eb.recurrence_end_date}T23:59:59`);
                }

                await this.supabaseFetch('rpc/create_schedule_block', 'POST', {
                    p_technician_id: this.scheduleManagement.selectedTechnicianId,
                    p_block_type: blockType,
                    p_start_at: startStr,
                    p_end_at: endStr,
                    p_is_recurring: eb.is_recurring,
                    p_recurrence_type: eb.is_recurring ? eb.recurrence_type : null,
                    p_recurrence_days: null,
                    p_reason: eb.notes || 'Bloqueio Administrativo',
                    p_recurrence_end_date: recurrenceEndDateStr
                });

                this.notify("Bloqueio salvo com sucesso!");
                this.closeBlockModal();
                this.loadScheduleManagement();
            } catch (e) {
                console.error(e);
                this.notify("Erro ao salvar bloqueio.", "error");
            } finally {
                this.loading = false;
            }
        },

        async removeBlock() {
            const eb = this.scheduleManagement.editingBlock;
            if (!eb.block_id) {
                this.notify("ID do bloqueio não encontrado.", "error");
                return;
            }

            if (!confirm("Remover este bloqueio?")) return;

            this.loading = true;
            try {
                await this.supabaseFetch('rpc/delete_schedule_block', 'POST', {
                    p_block_id: eb.block_id
                });
                this.notify("Bloqueio removido.");
                this.closeBlockModal();
                this.loadScheduleManagement();
            } catch (e) {
                console.error(e);
                this.notify("Erro ao remover bloqueio.", "error");
            } finally {
                this.loading = false;
            }
        },


        formatScheduleDateFull(dateStr) {
            if (!dateStr) return '';
            const d = new Date(dateStr + 'T12:00:00');
            return d.toLocaleDateString('pt-BR', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' });
        },


        formatAppointmentSummary(appt) {
            if (!appt) return '';
            const dayStr = this.formatScheduleDate(appt.date);
            const startStr = this.formatTimeOnly(appt.start);
            const endStr = this.formatTimeOnly(appt.end);
            return `${dayStr}, ${startStr} - ${endStr}`;
        },

        isFieldRequired(key) {
            return window.AIDAConfigHelpers.isFieldRequired(this.trackerConfig, key);
        },

        validateTicketRequirements(ticketData) {
            // If OS Generation is enabled, skip OS validation (server will fill it)
            const isOsAuto = this.isAutoOSGenerationEnabled();
            const skipsAnalysis = Boolean(this.ticketForm.budget_approved);

            const missing = [];

            this.TICKET_REQUIRED_FIELDS.forEach(field => {
                // Orçamento já aprovado começa depois da análise e não exige prazo/agenda dela.
                if (skipsAnalysis && ['analysis_deadline', 'analysis_schedule'].includes(field.key)) return;

                // Skip OS Number check if Auto-Gen is on
                if (field.key === 'os_number' && isOsAuto) return;

                if (this.isFieldRequired(field.key)) {
                    let isValid = true;
                    const val = ticketData[field.col];

                    if (field.type === 'text') {
                        if (!val || String(val).trim() === '') isValid = false;
                    } else if (field.type === 'date') {
                        if (!val) isValid = false;
                    } else if (field.type === 'array') {
                        if (!val || !Array.isArray(val) || val.length === 0) isValid = false;
                    } else if (field.type === 'id_check') {
                        if (ticketData.is_outsourced) {
                            if (!ticketData.outsourced_company_id) isValid = false;
                        } else {
                            if (!val) isValid = false; // Must have specific technician (Not NULL)
                        }
                    } else if (field.type === 'schedule') {
                        if (field.key === 'analysis_schedule') {
                            if (!this.selectedAnalysisAppointment) isValid = false;
                        } else if (field.key === 'repair_schedule') {
                            if (!this.selectedRepairAppointment) isValid = false;
                        }
                    }

                    if (!isValid) missing.push(field.label);
                }
            });

            return {
                valid: missing.length === 0,
                missing,
                missingFields: missing.map(label => {
                    const field = this.TICKET_REQUIRED_FIELDS.find(item => item.label === label);
                    return field ? field.key : null;
                }).filter(Boolean)
            };
        },

        viewTicketDetails(ticket) {
            // Establish Secure Context via Module
            const newContext = window.AIDATicketContext.setModalContext(ticket.id, 'viewTicket');
            this._applyContext(newContext);
            this.selectedTicket = ticket;

            if (!Array.isArray(this.selectedTicket.checklist_data)) this.selectedTicket.checklist_data = [];
            if (!Array.isArray(this.selectedTicket.checklist_final_data)) this.selectedTicket.checklist_final_data = [];
            if (!Array.isArray(this.selectedTicket.photos_urls)) this.selectedTicket.photos_urls = [];
            this.analysisForm = { needsParts: !!ticket.parts_needed, partsList: ticket.parts_needed || '' };
            this.editingDeadlines = false;
            this.editDeadlineForm = { deadline: '', analysis_deadline: '' };

            this.fetchInternalNotes(ticket.id);
            this.fetchTicketAppointments(ticket.id);
            this.newNoteText = '';
            this.noteIsChecklist = false;
            this.noteChecklistItems = [];

            this.modals.viewTicket = true;
        },

        startEditingDeadlines() {
            const ticket = this.resolveTicket();
            if (!ticket) return;
            const formatForInput = (dateStr) => {
                if (!dateStr) return '';
                const d = new Date(dateStr);
                const pad = (n) => n < 10 ? '0' + n : n;
                return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
            };

            this.editDeadlineForm.deadline = formatForInput(ticket.deadline);
            this.editDeadlineForm.analysis_deadline = formatForInput(ticket.analysis_deadline);
            this.editingDeadlines = true;
        },

        cancelEditingDeadlines() {
            this.editingDeadlines = false;
            this.editDeadlineForm = { deadline: '', analysis_deadline: '' };
        },

        async uploadTicketPhoto(file, ticketId) {
            try {
                this.loading = true;
                return await window.AIDAStorageService.uploadTicketPhoto(file, ticketId, {
                    SUPABASE_URL,
                    SUPABASE_KEY,
                    state: this
                });
            } catch (e) {
                this.notify("Erro upload: " + e.message, "error");
                return null;
            } finally {
                this.loading = false;
            }
        },

        // Helper to resolve view URLs
        async getPhotoUrl(input) {
            return await window.AIDAStorageService.getPhotoUrl(input, {
                SUPABASE_URL,
                SUPABASE_KEY,
                state: this
            });
        },

        async handlePhotoUpload(event, targetList = 'new') {
            const files = event.target.files;
            if (!files || files.length === 0) return;

            let ticketId;
            let targetArray;

            if (targetList === 'new') {
                // Para "Novo Ticket", ticketForm.id já existe (gerado no openNewTicketModal)
                // O upload agora usa workspaceId no path, então não depende de ticket existir no banco.
                ticketId = this.ticketForm.id;
                targetArray = this.ticketForm.photos;
            } else {
                const ticket = this.resolveTicket();
                if (!ticket || !ticket.id) {
                    this.notify("Erro: Ticket inválido.", "error");
                    return;
                }
                ticketId = ticket.id;
                // Important: modify the view model too since it's an un-saved state array sometimes
                if (!this.selectedTicket.photos_urls) this.selectedTicket.photos_urls = [];
                targetArray = this.selectedTicket.photos_urls;
            }

            for (let i = 0; i < files.length; i++) {
                const url = await this.uploadTicketPhoto(files[i], ticketId);
                if (url) {
                    targetArray.push(url);
                }
            }

            event.target.value = '';
        },

        removePhoto(index, targetList = 'new') {
             if (targetList === 'new') {
                 window.AIDAStorageService.forgetLocalPhotoPreview(this.ticketForm.photos[index]);
                 this.ticketForm.photos.splice(index, 1);
             } else {
                 if (this.selectedTicket && this.selectedTicket.photos_urls) {
                     window.AIDAStorageService.forgetLocalPhotoPreview(this.selectedTicket.photos_urls[index]);
                     this.selectedTicket.photos_urls.splice(index, 1);
                 }
             }
        },

        // --- SHARE TICKET ---
        getTrackingLink(ticket) {
            const baseUrl = window.location.origin + window.location.pathname.replace('index.html', '') + 'acompanhar.html';
            return `${baseUrl}?id=${ticket.id}&token=${ticket.public_token}`;
        },

        openShareModal() {
            if (!this.isModuleEnabled('public_tracker')) {
                this.notify('O acompanhamento público está desativado.', 'error');
                return;
            }
            const ticket = this.resolveTicket();
            if (ticket) {
                // Ensure public_token is available
                if (!ticket.public_token) {
                    // Fallback refresh logic if missing (should not happen often)
                    this.fetchTickets().then(() => {
                        const updated = this.tickets.find(t => t.id === ticket.id);
                        if(updated) this.selectedTicket = updated;
                    });
                }
                this.showShareModal = true;
            }
        },

        copyTrackingLink() {
             if (!this.isModuleEnabled('public_tracker')) return;
             const ticket = this.resolveTicket();
             if (!ticket) return;
             const link = this.getTrackingLink(ticket);
             navigator.clipboard.writeText(link).then(() => {
                 this.notify("Link copiado!");
             });
        },

        sendTrackingWhatsApp() {
            if (this.isWhatsAppDisabled()) return;
            if (!this.isModuleEnabled('public_tracker')) return this.notify('O acompanhamento público está desativado.', 'error');
            const ticket = this.resolveTicket();
            if (!ticket || !ticket.contact_info) return this.notify("Sem contato cadastrado", "error");

            const link = this.getTrackingLink(ticket);
            const msg = `Olá ${ticket.client_name}, acompanhe o progresso do seu reparo em tempo real aqui: ${link}`;

            let number = ticket.contact_info.replace(/\D/g, '');
            if (number.length <= 11) number = '55' + number;

            window.open(`https://wa.me/${number}?text=${encodeURIComponent(msg)}`, '_blank');
        },

        sendCarrierWhatsApp(ticket, carrier, trackingCode) {
            if (this.isWhatsAppDisabled()) return;
            if (!ticket || !ticket.contact_info) return;

            const link = this.getTrackingLink(ticket);
            let msg = `Olá ${ticket.client_name}, boa notícia! Seu aparelho ${ticket.device_model} (OS ${ticket.os_number}) foi enviado pela transportadora ${carrier}.`;

            if (trackingCode) {
                msg += ` Código de rastreio: ${trackingCode}.`;
            }

            if (this.isModuleEnabled('public_tracker')) {
                msg += ` Acompanhe o status aqui: ${link}`;
            }

            let number = ticket.contact_info.replace(/\D/g, '');
            if (number.length <= 11) number = '55' + number;

            window.open(`https://wa.me/${number}?text=${encodeURIComponent(msg)}`, '_blank');
        },

        // --- INTERNAL NOTES SYSTEM ---

        async fetchTicketAppointments(ticketId) {
            try {
                this.selectedTicketAppointments = [];
                const response = await this.supabaseFetch('rpc/get_ticket_appointments', 'POST', { p_ticket_id: ticketId });
                if (response && Array.isArray(response)) {
                    this.selectedTicketAppointments = response;
                }
            } catch (error) {
                console.error("Error fetching ticket appointments:", error);
            }
        },

        async fetchInternalNotes(ticketId) {
            return await window.AIDANotesService.fetchInternalNotes(ticketId, {
                state: this,
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload)
            });
        },

        async fetchGeneralNotes() {
            return await window.AIDANotesService.fetchGeneralNotes({
                state: this,
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload)
            });
        },

        // Mention Logic
        handleNoteInput(event, target) {
            const text = event.target.value;
            const cursorPos = event.target.selectionStart;

            const lastAt = text.lastIndexOf('@', cursorPos - 1);

            if (lastAt !== -1) {
                const potentialName = text.substring(lastAt + 1, cursorPos);
                if (!/\s/.test(potentialName)) {
                    this.showMentionList = true;
                    this.mentionQuery = potentialName;
                    this.mentionTarget = target;
                    this.mentionCursorPos = lastAt;
                    this.mentionList = this.employees.filter(e =>
                        e.name.toLowerCase().includes(potentialName.toLowerCase()) ||
                        e.username.toLowerCase().includes(potentialName.toLowerCase())
                    ).slice(0, 5);
                    return;
                }
            }
            this.showMentionList = false;
        },

        selectMention(employee) {
            const targetText = this.mentionTarget === 'general' ? this.newGeneralNoteText : this.newNoteText;
            const before = targetText.substring(0, this.mentionCursorPos);
            const after = targetText.substring(this.mentionCursorPos + this.mentionQuery.length + 1);

            const newText = `${before}@${employee.name} ${after}`;

            if (this.mentionTarget === 'general') {
                this.newGeneralNoteText = newText;
            } else {
                this.newNoteText = newText;
            }

            this.showMentionList = false;
        },

        // formatNoteContent was removed to eliminate x-html and innerHTML usage completely.

        async sendNote(ticketId = null, isGeneral = false) {
            return await window.AIDANotesService.sendNote(ticketId, isGeneral, {
                state: this,
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload),
                notify: (msg, type) => this.notify(msg, type),
                setLoading: (val) => { this.loading = val; },
                fetchGeneralNotes: () => this.fetchGeneralNotes(),
                fetchInternalNotes: (id) => this.fetchInternalNotes(id)
            });
        },

        addNoteChecklistItem(isGeneral = false) {
            const target = isGeneral ? this.generalNoteChecklistItems : this.noteChecklistItems;
            target.push({ text: '', ok: false });
        },

        removeNoteChecklistItem(index, isGeneral = false) {
            const target = isGeneral ? this.generalNoteChecklistItems : this.noteChecklistItems;
            target.splice(index, 1);
        },

        async toggleNoteCheckStatus(note, itemIndex) {
            return await window.AIDANotesService.toggleNoteCheckStatus(note, itemIndex, {
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload)
            });
        },

        async resolveNote(note) {
            return await window.AIDANotesService.resolveNote(note, {
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload),
                notify: (msg, type) => this.notify(msg, type)
            });
        },

        async archiveNote(note) {
            return await window.AIDANotesService.archiveNote(note, {
                state: this,
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload),
                notify: (msg, type) => this.notify(msg, type)
            });
        },

        // ==========================================
        // [MODULE PREPARATION] WORKFLOW & MUTATIONS
        // ==========================================
        // The following section is fully decoupled from global
        // isolated state (except activeTicketId resolution) and
        // is ready for extraction into `ticket-workflow.js`.

        // --- 1. WORKFLOW RULES ENGINE ---
        canExecuteAction(ticket, action) {
            return window.AIDAWorkflowRules.canExecuteAction(
                ticket,
                action,
                (role) => this.hasRole(role),
                this.trackerConfig
            );
        },

        // --- 2. CENTRALIZED MUTATION LAYER ---

        // Helper to bundle dependencies for the mutation module
        _getMutationDeps() {
            return {
                canExecuteAction: (t, a) => this.canExecuteAction(t, a),
                setLoading: (val) => { this.loading = val; },
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload),
                updateSelectedTicket: (id, updates) => {
                    if (this.selectedTicket && this.selectedTicket.id === id) {
                        this.selectedTicket = { ...this.selectedTicket, ...updates };
                    }
                },
                logTicketAction: (id, act, det) => this.logTicketAction(id, act, det),
                notify: (msg, type) => this.notify(msg, type),
                fetchTickets: () => this.refreshPostMutation(),
                closeViewModal: () => { this.modals.viewTicket = false; }
            };
        },

        async mutateTicket(ticket, actionName, updates = {}, actionLog = null, options = { showNotify: true, closeViewModal: false, fetchTickets: true }) {
            return await window.AIDATicketMutations.mutateTicket(
                ticket,
                actionName,
                updates,
                actionLog,
                options,
                this._getMutationDeps()
            );
        },

        // --- 4. POLÍTICA DE REFRESH PÓS-MUTAÇÃO ---
        async refreshPostMutation(forceListRefetch = false) {
            // Se foi especificado um refetch forçado (ex: createTicket) OU
            // se estivermos em uma view operacional que depende de consistência forte na UI após ações
            // (kanban, tech_orders, tester_bench, admin_dashboard, home/dashboard), disparamos o fetch.
            const operationalViews = ['kanban', 'tech_orders', 'tester_bench', 'admin_dashboard', 'home', 'dashboard'];
            const needsFetch = forceListRefetch || operationalViews.includes(this.view);

            if (needsFetch) {
                 if (this.view === 'dashboard' || this.view === 'home') {
                     await this.fetchHomeOperationalQueue();
                 } else {
                     await this.fetchTickets();
                 }
            }

            // Atualiza métricas ou alertas complementares dependendo da view
            if (this.view === 'dashboard' || this.view === 'admin_dashboard') {
                await this.requestDashboardMetrics({ reason: 'post_mutation' });
            } else if (this.view === 'kanban') {
                await this.fetchOperationalAlerts();
            }
        },

        // --- 3. WRAPPERS & ACTIONS ---

        // Helper to provide comprehensive dependencies to ticket-actions module
        _getActionDeps() {
            return {
                state: this, // Pass the whole Alpine component as state (read-only where possible, mutable for specific deep bindings)
                notify: (msg, type) => this.notify(msg, type),
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload),
                resolveTicket: (t) => this.resolveTicket(t),
                mutateTicket: (t, act, upd, log, opts) => this.mutateTicket(t, act, upd, log, opts),
                updateStatus: (t, st, upd, log) => this.updateStatus(t, st, upd, log),
                logTicketAction: (id, act, det) => this.logTicketAction(id, act, det),
                fetchTickets: (force = false) => this.refreshPostMutation(force),
                fetchGlobalLogs: () => this.fetchGlobalLogs(),
                fetchDeletedItems: () => this.fetchDeletedItems(),
                fetchEmployees: () => this.fetchEmployees(),
                getLogContext: (t) => this.getLogContext(t),
                escapeHtml: (str) => this.escapeHtml(str),
                toUTC: (date) => this.toUTC(date),
                isAutoOSGenerationEnabled: () => this.isAutoOSGenerationEnabled(),
                isWhatsAppDisabled: () => this.isWhatsAppDisabled(),
                isLogisticsEnabled: () => this.isLogisticsEnabled(),
                isPartsControlEnabled: () => this.isPartsControlEnabled(),
                isFinalTestEnabled: () => this.isFinalTestEnabled(),
                isTimerEnabled: (type) => this.isTimerEnabled(type),
                getDeliveryMode: () => this.getDeliveryMode(),
                isPriorityRequestEnabled: () => this.isPriorityRequestEnabled(),
                isAppointmentTypeEnabled: (type) => this.isAppointmentTypeEnabled(type),
                isModuleEnabled: (key) => this.isModuleEnabled(key),
                getOutsourcedCompany: (id) => this.getOutsourcedCompany(id),
                getOutsourcedPhone: (id) => this.getOutsourcedPhone(id),
                getTrackingLink: (t) => this.getTrackingLink(t),
                sendTrackingWhatsApp: () => this.sendTrackingWhatsApp(),
                sendCarrierWhatsApp: (t, c, tr) => this.sendCarrierWhatsApp(t, c, tr),
                validateTicketRequirements: (data) => this.validateTicketRequirements(data),
                isFieldRequired: (key) => this.isFieldRequired(key),
                isFieldVisible: (key) => this.isFieldVisible(key),
                focusTicketField: (field) => this.focusTicketField(field),
                focusTicketFields: (fields) => this.focusTicketFields(fields),
                setLoading: (val) => { this.loading = val; },
                closeModal: (name) => { this.modals[name] = false; },
                openLogisticsModal: (t) => this.openLogisticsModal(t),
                setEditingDeadlines: (val) => { this.editingDeadlines = val; }
            };
        },

        async updateStatus(ticket, newStatus, additionalUpdates = {}, actionLog = null) {
            return await window.AIDATicketMutations.updateStatus(
                ticket,
                newStatus,
                additionalUpdates,
                actionLog,
                this._getMutationDeps()
            );
        },

        // == SUBFASE 1 — FLUXO ADMINISTRATIVO BASE ==

        async createTicket() {
            if (!this.bypassAnalysisCheck && this.ticketForm.analysis_deadline && this.selectedAnalysisAppointment) {
                const deadlineDate = new Date(this.ticketForm.analysis_deadline);
                const appendDate = new Date(`${this.selectedAnalysisAppointment.date}T${this.selectedAnalysisAppointment.end}`);

                if (appendDate > deadlineDate) {
                    this.modals.confirmCreateTicket = true;
                    return;
                }
            }

            const result = await window.AIDATicketActions.createTicket(this._getActionDeps());
            this.bypassAnalysisCheck = false;
            return result;
        },

        async finishAnalysis(ticketOrId) {
            return await window.AIDATicketActions.finishAnalysis(ticketOrId, this._getActionDeps());
        },

        async approveRepair(ticketOrId) {
            return await window.AIDATicketActions.approveRepair(ticketOrId, this._getActionDeps());
        },

        async denyRepair(ticketOrId) {
            return await window.AIDATicketActions.denyRepair(ticketOrId, this._getActionDeps());
        },

        async confirmReceived(ticketOrId) {
            return await window.AIDATicketActions.confirmReceived(ticketOrId, this._getActionDeps());
        },

        async markDelivered(ticketOrId) {
            return await window.AIDATicketActions.markDelivered(ticketOrId, this._getActionDeps());
        },

        async saveDeadlines() {
            return await window.AIDATicketActions.saveDeadlines(this._getActionDeps());
        },

        async saveTicketChanges() {
            return await window.AIDATicketActions.saveTicketChanges(this._getActionDeps());
        },

        async deleteTicket(ticketOrId) {
            return await window.AIDATicketActions.deleteTicket(ticketOrId, this._getActionDeps());
        },

        async restoreItem(type, id) {
            return await window.AIDATicketActions.restoreItem(type, id, this._getActionDeps());
        },

        // == FIM SUBFASE 1 ==

        // == SUBFASE 2 — FLUXO TÉCNICO ==

        async startAnalysis(ticket) {
            return await window.AIDATicketActions.startAnalysis(ticket, this._getActionDeps());
        },

        async startTicketAnalysis(ticket) {
            return await window.AIDATicketActions.startTicketAnalysis(ticket, this._getActionDeps());
        },

        async startRepair(ticketOrId) {
            return await window.AIDATicketActions.startRepair(ticketOrId, this._getActionDeps());
        },

        canPauseRepairForParts(ticket) {
            if (!this.isPartsControlEnabled() || !ticket || ticket.status !== 'Andamento Reparo' || !ticket.repair_start_at) return false;
            if (this.hasRole('admin') || this.hasRole('atendente')) return true;
            return this.hasRole('tecnico') && ticket.technician_id === this.user?.id;
        },

        openPauseRepairForParts(ticketOrId) {
            const ticket = this.resolveTicket(ticketOrId);
            if (!ticket || !this.canPauseRepairForParts(ticket)) return;
            this.pauseRepairForPartsForm = { ticketId: ticket.id, parts: '' };
            this.modals.pauseRepairForParts = true;
        },

        async submitPauseRepairForParts() {
            return await window.AIDATicketActions.pauseRepairForParts(this.pauseRepairForPartsForm.ticketId, this._getActionDeps());
        },

        async finishRepair(success) {
            return await window.AIDATicketActions.finishRepair(success, this._getActionDeps());
        },

        async startTest(ticketOrId) {
            return await window.AIDATicketActions.startTest(ticketOrId, this._getActionDeps());
        },

        async concludeTest(success) {
            return await window.AIDATicketActions.concludeTest(success, this._getActionDeps());
        },

        async requestPriority(ticketOrId) {
            return await window.AIDATicketActions.requestPriority(ticketOrId, this._getActionDeps());
        },

        // == FIM SUBFASE 2 ==

        finishAnalysisFromKanban(ticket) {
            const newContext = window.AIDATicketContext.setModalContext(ticket.id, 'finishAnalysis');
            this._applyContext(newContext);
            this.selectedTicket = ticket;
            this.analysisForm = { needsParts: false, partsList: '' };
            this.modals.finishAnalysis = true;
        },

        async confirmFinishAnalysisKanban() {
            if (this.analysisForm.needsParts && !this.analysisForm.partsList) {
                return this.notify("Liste as peças necessárias.", "error");
            }
            this.modals.finishAnalysis = false;
            await this.finishAnalysis(this.resolveTicket());
        },

        openWhatsApp(phone) {
            if (!phone) return this.notify("Telefone não cadastrado.", "error");

            let number = phone.replace(/\D/g, '');

            if (number.length < 10) return this.notify("Número inválido para WhatsApp.", "error");

            if (number.length <= 11) {
                number = '55' + number;
            }

            window.open(`https://wa.me/${number}`, '_blank');
        },

        async startBudget(ticket) {
            this.viewTicketDetails(ticket);
        },

        openPurchaseModal(ticketOrId) {
            const ticket = this.resolveTicket(ticketOrId);
            if (!ticket) return;
            const newContext = window.AIDATicketContext.setModalContext(ticket.id, 'supplierPurchase');
            this._applyContext(newContext);
            this.purchaseFlow = {
                ticketId: ticket.id,
                supplierId: '',
                items: [{ name: ticket.parts_needed || '', quantity: 1 }]
            };
            this.modals.supplierPurchase = true;
        },

        addPurchaseItem() {
            this.purchaseFlow.items.push({ name: '', quantity: 1 });
        },

        removePurchaseItem(index) {
            this.purchaseFlow.items.splice(index, 1);
        },

        async markPurchased(ticketOrId) {
            // Replaced by openPurchaseModal, kept for compatibility if needed elsewhere
            this.openPurchaseModal(ticketOrId);
        },
        openOutcomeModal(mode, ticketOrId) {
            const ticket = this.resolveTicket(ticketOrId);
            if (!ticket) return;
            const newContext = window.AIDATicketContext.setModalContext(ticket.id, 'outcome');
            this._applyContext(newContext);
            this.selectedTicket = ticket; // Keep for UI bindings
            this.outcomeMode = mode;
            this.showTestFailureForm = false;
            this.modals.outcome = true;
        },

        // == SUBFASE 3 — TERCEIRIZAÇÃO / COMPRA / LOGÍSTICA ==

        async sendToOutsourced() {
            return await window.AIDATicketActions.sendToOutsourced(this._getActionDeps());
        },

        async receiveFromOutsourced(ticketOrId) {
            return await window.AIDATicketActions.receiveFromOutsourced(ticketOrId, this._getActionDeps());
        },

        cobrarOutsourced(ticket) {
            return window.AIDATicketActions.cobrarOutsourced(ticket, this._getActionDeps());
        },

        async submitPurchase() {
            return await window.AIDATicketActions.submitPurchase(this._getActionDeps());
        },

        async confirmLogisticsOption(type) {
            return await window.AIDATicketActions.confirmLogisticsOption(type, this._getActionDeps());
        },

        async confirmCarrier() {
            return await window.AIDATicketActions.confirmCarrier(this._getActionDeps());
        },

        async markAvailable(ticketOrId) {
            return await window.AIDATicketActions.markAvailable(ticketOrId, this._getActionDeps());
        },

        async sendBudget(ticketOrId) {
            return await window.AIDATicketActions.sendBudget(ticketOrId, this._getActionDeps());
        },

        // == FIM SUBFASE 3 ==

        // --- OUTSOURCED FUNCTIONS ---
        getOutsourcedCompany(id) {
             const c = this.outsourcedCompanies.find(x => x.id === id);
             return c ? c.name : 'Desconhecido';
        },
        getOutsourcedPhone(id) {
             const c = this.outsourcedCompanies.find(x => x.id === id);
             return c ? c.phone : '';
        },
        getOutsourcedServices(id) {
             const c = this.outsourcedCompanies.find(x => x.id === id);
             return c && c.services ? c.services : '';
        },

        openOutsourcedModal(ticketOrId) {
            const ticket = this.resolveTicket(ticketOrId);
            if (!ticket) return;
            const newContext = window.AIDATicketContext.setModalContext(ticket.id, 'outsourced');
            this._applyContext(newContext);
            this.selectedTicket = ticket; // Keep for UI bindings
            this.outsourcedForm = { company_id: ticket.outsourced_company_id, deadline: '', price: '' };
            this.modals.outsourced = true;
        },

        // --- LOGISTICS FUNCTIONS ---
        openLogisticsModal(ticketOrId) {
            const ticket = this.resolveTicket(ticketOrId);
            if (!ticket) return;
            const newContext = window.AIDATicketContext.setModalContext(ticket.id, 'logistics');
            this._applyContext(newContext);
            this.selectedTicket = ticket; // Keep for UI bindings
            this.logisticsMode = 'initial';
            this.logisticsForm = { carrier: '', tracking: '' };
            this.modals.logistics = true;
        },

        addTrackingCode(ticketOrId) {
            const ticket = this.resolveTicket(ticketOrId);
            if (!ticket) return;
            const newContext = window.AIDATicketContext.setModalContext(ticket.id, 'logistics');
            this._applyContext(newContext);
            this.selectedTicket = ticket; // Keep for UI bindings
            this.logisticsMode = 'add_tracking';
            this.logisticsForm = { carrier: ticket.carrier_name || '', tracking: '' };
            this.modals.logistics = true;
        },
        // ==========================================
        // END WORKFLOW MODULE
        // ==========================================

        // --- CALENDAR HELPERS ---
        getBenchCalendarSourceTickets() {
            let source = this.tickets.filter(t => t.status !== 'Finalizado');

            let effectiveFilter = this.adminDashboardFilters.technician;
            if (!this.hasRole('admin') && this.hasRole('tecnico')) {
                effectiveFilter = this.user.id;
            }

            if (effectiveFilter !== 'all' && effectiveFilter) {
                source = source.filter(t => t.technician_id === effectiveFilter);
            }

            return source;
        },

        getCalendarTickets() {
            if (!this.isFieldVisible('deadline')) return [];
            return this.getBenchCalendarSourceTickets().filter(t => t.deadline);
        },

        getBenchCalendarEvents() {
            const source = this.getBenchCalendarSourceTickets();
            const events = [];
            const addEvent = (ticket, eventType, eventDate) => {
                if (!eventDate || this.getValidTimestamp(eventDate) === null) return;
                if (this.showTodayOnly && !this.isSameDay(eventDate, new Date())) return;
                events.push({
                    key: `${ticket.id}:${eventType}:${eventDate}`,
                    ticket,
                    eventType,
                    eventDate
                });
            };

            source.forEach(ticket => {
                if (this.benchCalendarMode === 'appointment' && this.isModuleEnabled('agenda')) {
                    if (this.isAppointmentTypeEnabled('analysis')) addEvent(ticket, 'analysis', ticket.analysis_scheduled_at);
                    if (this.isAppointmentTypeEnabled('repair')) addEvent(ticket, 'repair', ticket.repair_scheduled_at);
                } else {
                    if (this.isFieldVisible('deadline')) addEvent(ticket, 'deadline', ticket.deadline);
                }
            });

            const typeOrder = { analysis: 0, repair: 1, deadline: 2 };
            return events.sort((a, b) => {
                const timeDiff = this.getValidTimestamp(a.eventDate) - this.getValidTimestamp(b.eventDate);
                if (timeDiff !== 0) return timeDiff;
                const typeDiff = typeOrder[a.eventType] - typeOrder[b.eventType];
                if (typeDiff !== 0) return typeDiff;
                return String(a.ticket.os_number || '').localeCompare(String(b.ticket.os_number || ''), undefined, { numeric: true });
            });
        },

        getBenchCalendarEventsForDay(day) {
            return this.getBenchCalendarEvents().filter(event => this.isSameDay(event.eventDate, day));
        },

        getCalendarModalEventsForDay(day) {
            if (this.view === 'kanban') {
                return this.getKanbanCalendarTickets()
                    .map(ticket => ({
                        key: `${ticket.id}:deadline:${ticket.deadline}`,
                        ticket,
                        eventType: 'deadline',
                        eventDate: ticket.deadline
                    }))
                    .filter(event => this.isSameDay(event.eventDate, day))
                    .sort((a, b) => this.getValidTimestamp(a.eventDate) - this.getValidTimestamp(b.eventDate));
            }
            return this.getBenchCalendarEventsForDay(day);
        },

        getCalendarEventClasses(event) {
            if (event?.eventType === 'analysis') {
                return 'bg-orange-50 border-orange-200 text-orange-800 hover:bg-orange-100';
            }
            if (event?.eventType === 'repair') {
                return 'bg-blue-50 border-blue-200 text-blue-800 hover:bg-blue-100';
            }
            return 'bg-slate-50 border-slate-200 text-slate-700 hover:bg-slate-100';
        },

        getCalendarEventTypeLabel(event) {
            if (event?.eventType === 'analysis') return 'Análise';
            if (event?.eventType === 'repair') return 'Reparo';
            return 'Prazo';
        },

        getCalendarEventIcon(event) {
            if (event?.eventType === 'analysis') return 'fa-magnifying-glass';
            if (event?.eventType === 'repair') return 'fa-screwdriver-wrench';
            return 'fa-flag-checkered';
        },

        formatCalendarEventTime(value) {
            const date = new Date(value);
            if (!Number.isFinite(date.getTime())) return '--:--';
            return date.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
        },

        openCalendarEvent(event) {
            const ticket = event?.ticket || event;
            if (!ticket?.id) return;
            this.modals.calendar = false;
            if (this.view === 'tech_orders') {
                this.viewTicketDetails(ticket);
                return;
            }
            this.scrollToTicket(ticket.id);
        },

        getKanbanCalendarTickets() {
            return this.tickets.filter(t => t.status !== 'Finalizado' && t.deadline);
        },

        scrollToTicket(ticketId) {
            setTimeout(() => {
                const el = document.getElementById('ticket-card-' + ticketId);
                if (el) {
                    el.scrollIntoView({ behavior: 'smooth', block: 'center', inline: 'center' });
                    el.classList.add('ring-4', 'ring-brand-500', 'ring-opacity-75', 'z-10');
                    setTimeout(() => {
                        el.classList.remove('ring-4', 'ring-brand-500', 'ring-opacity-75', 'z-10');
                    }, 2000);
                } else {
                    console.warn("Ticket card not found:", ticketId);
                }
            }, 100);
        },

        initKanbanScroll() {
            const content = document.getElementById('kanban-content');
            if (content) {
                this.kanbanScrollWidth = content.scrollWidth;
                const ro = new ResizeObserver(() => {
                    this.kanbanScrollWidth = content.scrollWidth;
                });
                ro.observe(content);
            }
        },

        getWeekDays() {
            const curr = new Date();
            const first = curr.getDate() - curr.getDay();
            const days = [];
            for (let i = 0; i < 7; i++) {
                let next = new Date(curr.getTime());
                next.setDate(first + i);
                days.push(next);
            }
            return days;
        },

        getMonthDays() {
            const year = this.currentCalendarDate.getFullYear();
            const month = this.currentCalendarDate.getMonth();
            const date = new Date(year, month, 1);
            const days = [];

            for(let i=0; i<date.getDay(); i++) {
                days.push(null);
            }

            while (date.getMonth() === month) {
                days.push(new Date(date));
                date.setDate(date.getDate() + 1);
            }
            return days;
        },

        changeMonth(step) {
            const newDate = new Date(this.currentCalendarDate);
            newDate.setMonth(newDate.getMonth() + step);
            this.currentCalendarDate = newDate;
        },

        isSameDay(d1, d2) {
            if (!d1 || !d2) return false;
            const date1 = new Date(d1);
            const date2 = new Date(d2);
            return date1.getDate() === date2.getDate() &&
                   date1.getMonth() === date2.getMonth() &&
                   date1.getFullYear() === date2.getFullYear();
        },
        // --- COMBOBOX HELPERS ---
        deviceModelCombobox() {
            return {
                open: false,
                search: '',
                highlightedIndex: -1,
                init() {
        this.search = this.ticketForm.model || '';
                    this.$watch('ticketForm.model', (val) => {
                        if (!this.open) this.search = val || '';
                    });
                    this.$watch('search', () => {
                        this.highlightedIndex = -1;
                    });
                },
                toggleArrow() {
                    if (this.open) {
                        this.closeDropdown();
                    } else {
                        this.open = true;
                        this.search = ''; // Open with clear search to see all options
                        this.highlightedIndex = -1;
                        this.$nextTick(() => this.$refs.searchInput.focus());
                    }
                },
                onInput() {
                    this.open = true;
                    this.ticketForm.model = this.search;
                },
                onFocus() {
                    // Only overwrite search if we are NOT opening it explicitly via arrow
                    if (!this.open) {
                        this.open = true;
                        this.search = this.ticketForm.model || '';
                        this.highlightedIndex = -1;
                    }
                },
                selectOption(modelName) {
                    this.ticketForm.model = modelName;
                    this.search = modelName;
                    this.open = false;
                    this.highlightedIndex = -1;
                },
                closeDropdown() {
                    if (this.open) {
                        this.open = false;
                        this.search = this.ticketForm.model || ''; // Restore input value to bound state
                        this.highlightedIndex = -1;
                    }
                },
                onKeydown(e) {
                    if (!this.open) {
                        if (e.key === 'ArrowDown' || e.key === 'Enter') {
                            e.preventDefault();
                            this.open = true;
                        }
                        return;
                    }
                    const options = this.deviceModels.filter(m => m.name.toLowerCase().includes(this.search.toLowerCase()));
                    if (e.key === 'ArrowDown') {
                        e.preventDefault();
                        if (options.length > 0) {
                            this.highlightedIndex = (this.highlightedIndex + 1) % options.length;
                            this.scrollToHighlighted();
                        }
                    } else if (e.key === 'ArrowUp') {
                        e.preventDefault();
                        if (options.length > 0) {
                            this.highlightedIndex = this.highlightedIndex <= 0 ? options.length - 1 : this.highlightedIndex - 1;
                            this.scrollToHighlighted();
                        }
                    } else if (e.key === 'Enter') {
                        e.preventDefault();
                        if (this.highlightedIndex >= 0 && this.highlightedIndex < options.length) {
                            this.selectOption(options[this.highlightedIndex].name);
                        } else if (this.search.trim().length > 0 && !options.some(m => m.name.toLowerCase() === this.search.trim().toLowerCase())) {
                            // Criar novo se não houver destacada e não existir exato
                            this.createDeviceModel(this.search).then(ok => {
                                if(ok) { this.selectOption(this.search); }
                            });
                        }
                    } else if (e.key === 'Escape') {
                        this.closeDropdown();
                    }
                },
                scrollToHighlighted() {
                    this.$nextTick(() => {
                        const list = this.$refs.listbox;
                        if (!list) return;
                        const items = list.querySelectorAll('li.combobox-option');
                        const item = items[this.highlightedIndex];
                        if (item) {
                            item.scrollIntoView({ block: 'nearest' });
                        }
                    });
                }
            };
        },

        ticketCombobox() {
            return {
                open: false,
                search: '',
                highlightedIndex: -1,
                init() {
        this.$watch('search', () => {
                        this.highlightedIndex = -1;
                    });
                },
                getFilteredTickets() {
                    const eaType = this.scheduleManagement.editingAppointment?.type;

                    // Combine and deduplicate tickets from unscheduled, withoutTechnician, and lateWithoutSchedule lists
                    const combined = [
                        ...this.scheduleManagement.unscheduledItems,
                        ...this.scheduleManagement.withoutTechnicianItems,
                        ...this.scheduleManagement.lateWithoutScheduleItems
                    ];

                    const uniqueMap = new Map();
                    combined.forEach(t => uniqueMap.set(t.id, t));
                    let tickets = Array.from(uniqueMap.values());

                    // Filter based on appointment type strictly
                    if (eaType === 'analysis') {
                        tickets = tickets.filter(t => t.status === 'Analise Tecnica');
                    } else if (eaType === 'repair') {
                        // Most non-analysis pending statuses can be booked as repair, but normally "Andamento Reparo"
                        // is the classic state. Let's allow anything that isn't explicitly analysis or finished.
                        tickets = tickets.filter(t => t.status !== 'Analise Tecnica' && t.status !== 'Finalizado' && t.status !== 'Retirada Cliente');
                    }

                    // Search filter
                    if (this.search.trim()) {
                        const q = this.search.toLowerCase().trim();
                        tickets = tickets.filter(t =>
                            (t.client_name && t.client_name.toLowerCase().includes(q)) ||
                            (t.os_number && t.os_number.toLowerCase().includes(q)) ||
                            (t.device_model && t.device_model.toLowerCase().includes(q))
                        );
                    }

                    return tickets;
                },
                toggleArrow() {
                    if (this.open) {
                        this.closeDropdown();
                    } else {
                        this.open = true;
                        this.search = '';
                        this.highlightedIndex = -1;
                        this.$nextTick(() => this.$refs.ticketSearch?.focus());
                    }
                },
                onInput() {
                    this.open = true;
                },
                onFocus() {
                    this.open = true;
                    this.highlightedIndex = -1;
                },
                selectOption(ticket) {
                    // When a ticket is selected from the combobox, populate the editingAppointment
                    this.scheduleManagement.editingAppointment.ticket_id = ticket.id;
                    this.scheduleManagement.editingAppointment.ticketContext = ticket;

                    // Attempt to pre-fill notes or extra context if needed here
                    this.search = '';
                    this.open = false;
                    this.highlightedIndex = -1;
                },
                closeDropdown() {
                    if (this.open) {
                        this.open = false;
                        this.highlightedIndex = -1;
                    }
                },
                onKeydown(e) {
                    if (!this.open) {
                        if (e.key === 'ArrowDown' || e.key === 'Enter') {
                            e.preventDefault();
                            this.open = true;
                        }
                        return;
                    }
                    const options = this.getFilteredTickets();
                    if (e.key === 'ArrowDown') {
                        e.preventDefault();
                        if (options.length > 0) {
                            this.highlightedIndex = (this.highlightedIndex + 1) % options.length;
                            this.scrollToHighlighted();
                        }
                    } else if (e.key === 'ArrowUp') {
                        e.preventDefault();
                        if (options.length > 0) {
                            this.highlightedIndex = this.highlightedIndex <= 0 ? options.length - 1 : this.highlightedIndex - 1;
                            this.scrollToHighlighted();
                        }
                    } else if (e.key === 'Enter') {
                        e.preventDefault();
                        if (this.highlightedIndex >= 0 && this.highlightedIndex < options.length) {
                            this.selectOption(options[this.highlightedIndex]);
                        }
                    } else if (e.key === 'Escape') {
                        this.closeDropdown();
                    }
                },
                scrollToHighlighted() {
                    this.$nextTick(() => {
                        const list = this.$refs.listbox;
                        if (!list) return;
                        const items = list.querySelectorAll('li.combobox-option');
                        const item = items[this.highlightedIndex];
                        if (item) {
                            item.scrollIntoView({ block: 'nearest' });
                        }
                    });
                }
            };
        },

        defectCombobox() {
            return {
                open: false,
                search: '',
                highlightedIndex: -1,
                init() {
        this.$watch('search', () => {
                        this.highlightedIndex = -1;
                    });
                },
                toggleArrow() {
                    if (this.open) {
                        this.closeDropdown();
                    } else {
                        this.open = true;
                        this.search = ''; // Open with clear search to see all options
                        this.highlightedIndex = -1;
                        this.$nextTick(() => this.$refs.defectSearch.focus());
                    }
                },
                onInput() {
                    this.open = true;
                },
                onFocus() {
                    this.open = true;
                    this.highlightedIndex = -1;
                },
                selectOption(defectName) {
                    this.addDefectToTicket(defectName);
                    this.search = '';
                    this.open = false;
                    this.highlightedIndex = -1;
                    this.$nextTick(() => this.$refs.defectSearch.focus());
                },
                closeDropdown() {
                    if (this.open) {
                        this.open = false;
                        this.search = ''; // Reset search string completely
                        this.highlightedIndex = -1;
                    }
                },
                onKeydown(e) {
                    if (!this.open) {
                        if (e.key === 'ArrowDown' || e.key === 'Enter') {
                            e.preventDefault();
                            this.open = true;
                        }
                        return;
                    }
                    const options = this.defectOptions.filter(d => d.name.toLowerCase().includes(this.search.toLowerCase()));
                    if (e.key === 'ArrowDown') {
                        e.preventDefault();
                        if (options.length > 0) {
                            this.highlightedIndex = (this.highlightedIndex + 1) % options.length;
                            this.scrollToHighlighted();
                        }
                    } else if (e.key === 'ArrowUp') {
                        e.preventDefault();
                        if (options.length > 0) {
                            this.highlightedIndex = this.highlightedIndex <= 0 ? options.length - 1 : this.highlightedIndex - 1;
                            this.scrollToHighlighted();
                        }
                    } else if (e.key === 'Enter') {
                        e.preventDefault();
                        if (this.highlightedIndex >= 0 && this.highlightedIndex < options.length) {
                            this.selectOption(options[this.highlightedIndex].name);
                        } else if (this.search.trim().length > 0 && !options.some(d => d.name.toLowerCase() === this.search.trim().toLowerCase())) {
                            // Criar novo se não houver destacada e não existir exato
                            this.createDefectOption(this.search).then(ok => {
                                if(ok) { this.selectOption(this.search); }
                            });
                        }
                    } else if (e.key === 'Escape') {
                        this.closeDropdown();
                    }
                },
                scrollToHighlighted() {
                    this.$nextTick(() => {
                        const list = this.$refs.listbox;
                        if (!list) return;
                        const items = list.querySelectorAll('li.combobox-option');
                        const item = items[this.highlightedIndex];
                        if (item) {
                            item.scrollIntoView({ block: 'nearest' });
                        }
                    });
                }
            };
        },

        addDefectToTicket(defectName) {
            const trimmed = defectName.trim();
            if (!trimmed) return;
            const existing = this.ticketForm.defects || [];
            if (existing.some(defect => defect.toLowerCase() === trimmed.toLowerCase())) return;
            this.ticketForm.defects = [...existing, trimmed];
        },
        removeDefectFromTicket(defectName) {
            this.ticketForm.defects = (this.ticketForm.defects || []).filter(defect => defect !== defectName);
        },
        getDefectList(defectReported) {
            if (!defectReported) return [];
            if (Array.isArray(defectReported)) {
                return defectReported.map(defect => defect.trim()).filter(Boolean);
            }
            return String(defectReported)
                .split(',')
                .map(defect => defect.trim())
                .filter(Boolean);
        },

        // --- UTILS ---
        // Removed safeLogHTML entirely to eliminate innerHTML usage.
        // We now rely on escapeHtml and direct parsing for text nodes.

        escapeHtml(text) {
            if (!text) return '';
            return text
                .replace(/&/g, "&amp;")
                .replace(/</g, "&lt;")
                .replace(/>/g, "&gt;")
                .replace(/"/g, "&quot;")
                .replace(/'/g, "&#039;");
        },

        getLogContext(ticket) {
            if (!ticket) return { client: 'Cliente', device: 'Aparelho' };

            const safeClientName = ticket.client_name || '';
            const safeOsNumber = ticket.os_number || '';
            const safeDevice = ticket.device_model || '';

            let client = `**${safeClientName}** da OS **${safeOsNumber}**`;
            const device = `**${safeDevice}**`;

            // Add outsourced context if applicable as requested by user
            if (ticket.is_outsourced && ticket.outsourced_company_id) {
                const company = this.getOutsourcedCompany(ticket.outsourced_company_id);
                client += ` (Terceirizado: **${company}**)`;
            }

            return { client, device };
        },

        getStatusLabel(status) {
            return this.STATUS_LABELS[status] || status;
        },

        getTechnicians() {
            return this.employees.filter(e => e.roles && e.roles.includes('tecnico'));
        },

        getEmployeeName(id) {
            if (!id) return 'Todos';
            const emp = this.employees.find(e => e.id === id);
            return emp ? emp.name : 'Desconhecido';
        },

        initTechFilter() {
            console.log("Initializing Tech Filter. User:", this.user);

            if (this.hasRole('admin')) {
                this.adminDashboardFilters.technician = 'all';
            } else if (this.hasRole('tecnico') && this.user && this.user.id) {
                this.adminDashboardFilters.technician = this.user.id;
                console.log("Filter set to self (Tech):", this.adminDashboardFilters.technician);
            } else {
                this.adminDashboardFilters.technician = 'all';
            }
        },

        getPriorityColor(prio) {
            switch(prio) {
                case 'Urgente': return 'bg-red-100 text-red-800 border-red-500';
                case 'Alta': return 'bg-orange-100 text-orange-800 border-orange-500';
                case 'Normal': return 'bg-blue-100 text-blue-800 border-blue-500';
                default: return 'bg-gray-100 text-gray-800 border-gray-300';
            }
        },

        getCardColor(ticket) {
            if (ticket.deadline && new Date(ticket.deadline) < new Date() && ticket.status !== 'Finalizado') {
                return 'border-l-4 border-red-600 bg-red-50';
            }
            return 'bg-white';
        },

        // --- PREVIEW LOGIC (Mirrors acompanhar.html) ---
        getPreviewDisplayedStatus() {
            const currentStatus = this.previewStatus;
            const visibleSteps = (this.trackerConfig.visible_stages && this.trackerConfig.visible_stages.length > 0)
                ? this.trackerConfig.visible_stages
                : this.STATUS_COLUMNS;

            const visibleSet = new Set(visibleSteps);

            // If status is visible, show it
            if (visibleSet.has(currentStatus)) {
                return currentStatus;
            }

            // If hidden, find previous visible
            const actualIdx = this.STATUS_INDEX_MAP[currentStatus] ?? -1;
            if (actualIdx === -1) return currentStatus;

            for (let i = actualIdx - 1; i >= 0; i--) {
                if (visibleSet.has(this.STATUS_COLUMNS[i])) {
                    return this.STATUS_COLUMNS[i];
                }
            }

            // Fallback
            return visibleSteps[0] || 'Aberto';
        },

        getPreviewProgressPercent() {
            const displayed = this.getPreviewDisplayedStatus();
            const visibleSteps = (this.trackerConfig.visible_stages && this.trackerConfig.visible_stages.length > 0)
                ? this.trackerConfig.visible_stages
                : this.STATUS_COLUMNS;

            const idx = visibleSteps.indexOf(displayed);
            if (idx === -1) return 0;
            if (visibleSteps.length <= 1) return 0;

            return (idx / (visibleSteps.length - 1)) * 100;
        },

        // DASHBOARD OPERATIONAL METRICS (RPC)
        async fetchOperationalAlerts() {
            if (this.opsInFlight) return;
            this.opsInFlight = true;
            try {
                const data = await window.AIDADashboardService.fetchOperationalAlerts({
                    state: this,
                    supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload)
                });
                if (data) {
                    this.ops = data;
                }
            } finally {
                this.opsInFlight = false;
            }
        },

        applyQuickFilter(type) {
            // Quick filters might need server support or just local filter on the 'Active' set?
            // If they are complicated, we might want to do them on server.
            // For now, let's keep them local if they operate on the Kanban set.
            this.searchQuery = '';
            this.view = 'kanban';
            this.activeQuickFilter = type;
            // Force re-render of Kanban
        },

        clearFilters() {
            this.searchQuery = '';
            this.activeQuickFilter = null;
            this.columnFilters = {};
            if (this.view === 'dashboard') {
                this.resetHomeOperationalFilters();
            } else if (this.view === 'kanban') {
                this.resetKanbanOperationalFilters();
            }
            this.fetchTickets();
        },

        isHomeOperationalFilterActive() {
            const f = this.homeOperationalFilters || {};
            const hasSearch = !!String(f.search || '').trim();
            return (
                f.window !== 'all' ||
                f.basis !== 'auto' ||
                f.status !== 'all' ||
                f.technician !== 'all' ||
                hasSearch
            );
        },

        isKanbanOperationalFilterActive() {
            const f = this.kanbanOperationalFilters || {};
            const hasSearch = !!String(f.search || '').trim();
            return (
                f.window !== 'all' ||
                f.basis !== 'auto' ||
                f.status !== 'all' ||
                f.technician !== 'all' ||
                hasSearch
            );
        },

        resetHomeOperationalFilters() {
            this.homeOperationalFilters = {
                window: 'all',
                basis: 'auto',
                status: 'all',
                technician: 'all',
                search: ''
            };
        },

        resetKanbanOperationalFilters() {
            this.kanbanOperationalFilters = {
                window: 'all',
                basis: 'auto',
                status: 'all',
                technician: 'all',
                search: ''
            };
        },

        applyHomeOperationalWindow(windowType) {
            this.closeOverviewQueueModal();
            this.homeOperationalFilters.window = windowType;
            if (this.homeOperationalFilters.basis === 'all') this.homeOperationalFilters.basis = 'auto';
            this.fetchHomeOperationalQueue();
        },

        applyHomeOperationalBasis(basisType) {
            this.homeOperationalFilters.basis = basisType;
            this.fetchHomeOperationalQueue();
        },

        applyKanbanOperationalWindow(windowType) {
            this.kanbanOperationalFilters.window = windowType;
            if (this.kanbanOperationalFilters.basis === 'all') this.kanbanOperationalFilters.basis = 'auto';
            this.fetchTickets();
        },

        applyKanbanOperationalBasis(basisType) {
            this.kanbanOperationalFilters.basis = basisType;
            this.fetchTickets();
        },

        getHomeOpsTotal(key) {
            return Number(this.homeOpsTotals?.[key] || 0);
        },

        getHomeOpsRemaining(key) {
            const shown = Array.isArray(this.homeOps?.[key]) ? this.homeOps[key].length : 0;
            return Math.max(0, this.getHomeOpsTotal(key) - shown);
        },

        getOverviewQueueTitle(key) {
            const titles = {
                pendingBudgets: 'Aguardando Envio de Orçamento',
                waitingBudgetResponse: 'Aguardando Aprovação',
                pendingPickups: 'Logística e expedição pendente',
                pendingTracking: 'Gerar Rastreio',
                pendingDelivery: 'Liberado',
                pendingTech: 'Aguardando Início',
                outsourcedToSend: 'Pendente Envio ao Terceirizado',
                pendingOutsourced: 'Aguardando Retorno do Terceirizado',
                pendingPurchase: 'Aguardando Compra',
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
