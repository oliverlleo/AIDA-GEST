
// Configuração do Supabase
const SUPABASE_URL = 'https://cpydazjwlmssbzzsurxu.supabase.co';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNweWRhemp3bG1zc2J6enN1cnh1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc4Mjg5MTUsImV4cCI6MjA4MzQwNDkxNX0.NM7cuB6mks74ZzfvMYhluIjnqBXVgtolHbN4huKmE-Q';

// Safe initialization
let supabaseClient;
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

let isUnloading = false;
window.addEventListener('beforeunload', () => { isUnloading = true; });

function app() {
    return {
        // State
        loading: false,
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
            urgentAnalysis: [],
            delayedDeliveries: [],
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
            is_outsourced: false, outsourced_company_id: '', // New fields
            checklist: [], checklist_final: [], photos: [], notes: ''
        },
        newChecklistItem: '',
        selectedTemplateId: '',
        newTemplateName: '',
        newChecklistFinalItem: '',
        selectedTemplateIdFinal: '',
        newTemplateNameFinal: '',

        // UI State for Actions
        analysisForm: { needsParts: false, partsList: '' },
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
        showAllCalendarTickets: false,

        // Kanban State
        kanbanScrollWidth: 0,
        columnFilters: {}, // { 'Aberto': { sort: 'default', search: '', dateStart: '', dateEnd: '' } }

        // Search
        searchQuery: '', // Global search
        activeQuickFilter: null,

        // Time
        currentTime: new Date(),

        // Modals
        modals: { newEmployee: false, editEmployee: false, ticket: false, viewTicket: false, outcome: false, logs: false, calendar: false, notifications: false, recycleBin: false, logistics: false, outsourced: false, forceChangePassword: false, resetPassword: false, finishAnalysis: false, fornecedor: false, supplierPurchase: false },

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
            { key: 'client_name', label: 'Cliente', col: 'client_name', type: 'text' },
            { key: 'contact_info', label: 'Contato', col: 'contact_info', type: 'text' },
            { key: 'os_number', label: 'Nº OS (Manual)', col: 'os_number', type: 'text' },
            { key: 'serial_number', label: 'Nº Série / IMEI', col: 'serial_number', type: 'text' },
            { key: 'priority', label: 'Prioridade', col: 'priority', type: 'text' },
            { key: 'device_model', label: 'Modelo', col: 'device_model', type: 'text' },
            { key: 'analysis_deadline', label: 'Prazo de Análise', col: 'analysis_deadline', type: 'date' },
            { key: 'deadline', label: 'Prazo de Entrega', col: 'deadline', type: 'date' },
            { key: 'device_condition', label: 'Situação do Aparelho', col: 'device_condition', type: 'text' },
            { key: 'responsible', label: 'Técnico Responsável', col: 'technician_id', type: 'id_check' },
            { key: 'defect_reported', label: 'Defeito Relatado', col: 'defect_reported', type: 'text' },
            { key: 'checklist_entry', label: 'Checklist de Entrada', col: 'checklist_data', type: 'array' },
            { key: 'checklist_exit', label: 'Checklist de Saída', col: 'checklist_final_data', type: 'array' },
            { key: 'photos', label: 'Fotos', col: 'photos_urls', type: 'array' }
        ],

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
        async supabaseFetch(endpoint, method = 'GET', body = null) {
            return await window.AIDAApiClient.supabaseFetch(endpoint, method, body, {
                SUPABASE_URL,
                SUPABASE_KEY,
                state: this
            });
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
                    this.fetchFornecedores()
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
                } else if (currentView === 'admin_dashboard') {
                    await this.fetchTickets();
                    await this.requestDashboardMetrics({ reason: 'open_admin_dashboard' });
                } else if (currentView === 'kanban') {
                    await this.fetchTickets();
                    await this.fetchOperationalAlerts(); // Alerts are used in kanban header
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

            console.log("App initializing...");
            this.loading = true;

            if (!supabaseClient) {
                this.notify("Erro crítico: Supabase não carregou.", "error");
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
                                this.trackerConfig = {
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
                                };
                            }

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
                    // Update OPS (RPC)
                    await this.fetchOperationalAlerts();

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
                    return this.STATUS_COLUMNS.indexOf(a) - this.STATUS_COLUMNS.indexOf(b);
                });
            }
        },

        // --- LOGGING ---
        async logTicketAction(ticketId, action, details = null) {
            return await window.AIDALogsNotificationsService.logTicketAction(ticketId, action, details, {
                state: this,
                supabaseFetch: (ep, method, payload) => this.supabaseFetch(ep, method, payload),
                fetchGlobalLogs: () => this.fetchGlobalLogs()
            });
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
                this.fetchTickets();
                if (this.view === 'dashboard') this.requestDashboardMetrics({ reason: 'search' });
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
                        this.techTickets = this.tickets.sort((a, b) => {
                            if (a.priority_requested && !b.priority_requested) return -1;
                            if (!a.priority_requested && b.priority_requested) return 1;
                            const dA = a.deadline ? new Date(a.deadline).getTime() : 9999999999999;
                            const dB = b.deadline ? new Date(b.deadline).getTime() : 9999999999999;
                            if (dA !== dB) return dA - dB;
                            const pOrder = { 'Urgente': 0, 'Alta': 1, 'Normal': 2, 'Baixa': 3 };
                            return (pOrder[a.priority] || 2) - (pOrder[b.priority] || 2);
                        });
                    } else {
                        let relevantTickets = this.tickets;
                        const isTechOnly = !this.hasRole('admin') && this.hasRole('tecnico');
                        if (isTechOnly && this.user) {
                            relevantTickets = relevantTickets.filter(t => t.technician_id == this.user.id || t.technician_id == null);
                        }

                        this.techTickets = relevantTickets.filter(t =>
                            ['Analise Tecnica', 'Andamento Reparo'].includes(t.status)
                        ).sort((a, b) => {
                            if (a.priority_requested && !b.priority_requested) return -1;
                            if (!a.priority_requested && b.priority_requested) return 1;
                            const dA = a.deadline ? new Date(a.deadline).getTime() : 9999999999999;
                            const dB = b.deadline ? new Date(b.deadline).getTime() : 9999999999999;
                            if (dA !== dB) return dA - dB;
                            const pOrder = { 'Urgente': 0, 'Alta': 1, 'Normal': 2, 'Baixa': 3 };
                            return (pOrder[a.priority] || 2) - (pOrder[b.priority] || 2);
                        });
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

        async createOutsourcedCompany(name, phone) {
            return await window.AIDACatalogService.createOutsourcedCompany(name, phone, {
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

        openNewTicketModal() {
            this.ticketForm = {
                id: crypto.randomUUID(),
                client_name: '', os_number: '', model: '', serial: '',
                defects: [], priority: 'Normal', contact: '',
                deadline: '', analysis_deadline: '', device_condition: '',
                technician_id: '',
                is_outsourced: false, outsourced_company_id: '',
                checklist: [], checklist_final: [], photos: [], notes: ''
            };
            this.modals.ticket = true;
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

        isFieldRequired(key) {
            return window.AIDAConfigHelpers.isFieldRequired(this.trackerConfig, key);
        },

        validateTicketRequirements(ticketData) {
            // If OS Generation is enabled, skip OS validation (server will fill it)
            const isOsAuto = this.isAutoOSGenerationEnabled();

            if (!this.isRequiredFieldsEnabled()) {
                // Legacy Validation (Hardcoded + Deadlines)
                if (!ticketData.client_name || (!isOsAuto && !ticketData.os_number) || !ticketData.device_model || !ticketData.defect_reported) {
                    return { valid: false, missing: ['Campos Padrão (*)'] };
                }
                if (!ticketData.analysis_deadline) return { valid: false, missing: ['Prazo de Análise'] };
                if (!ticketData.deadline) return { valid: false, missing: ['Prazo de Entrega'] };

                if (ticketData.is_outsourced) {
                    if (!ticketData.outsourced_company_id) return { valid: false, missing: ['Empresa Parceira'] };
                } else {
                    // In legacy mode, technician_id can be NULL (Todos)
                }
                return { valid: true };
            }

            const missing = [];
            const reqConfig = this.trackerConfig.required_ticket_fields || {};

            this.TICKET_REQUIRED_FIELDS.forEach(field => {
                // Skip OS Number check if Auto-Gen is on
                if (field.key === 'os_number' && isOsAuto) return;

                if (reqConfig[field.key]) {
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
                    }

                    if (!isValid) missing.push(field.label);
                }
            });

            return {
                valid: missing.length === 0,
                missing: missing
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
                 this.ticketForm.photos.splice(index, 1);
             } else {
                 if (this.selectedTicket && this.selectedTicket.photos_urls) {
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
             const ticket = this.resolveTicket();
             if (!ticket) return;
             const link = this.getTrackingLink(ticket);
             navigator.clipboard.writeText(link).then(() => {
                 this.notify("Link copiado!");
             });
        },

        sendTrackingWhatsApp() {
            if (this.isWhatsAppDisabled()) return;
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

            msg += ` Acompanhe o status aqui: ${link}`;

            let number = ticket.contact_info.replace(/\D/g, '');
            if (number.length <= 11) number = '55' + number;

            window.open(`https://wa.me/${number}?text=${encodeURIComponent(msg)}`, '_blank');
        },

        // --- INTERNAL NOTES SYSTEM ---

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

        formatNoteContent(text) {
            if (!text) return '';
            let safe = text
                .replace(/&/g, "&amp;")
                .replace(/</g, "&lt;")
                .replace(/>/g, "&gt;")
                .replace(/"/g, "&quot;")
                .replace(/'/g, "&#039;");

            safe = safe.replace(/@(\w+(\s\w+)?)/g, '<span class="text-brand-500 font-bold">@$1</span>');

            return safe.replace(/\n/g, '<br>');
        },

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
            // (kanban, tech_orders, tester_bench, admin_dashboard), disparamos o fetch.
            const operationalViews = ['kanban', 'tech_orders', 'tester_bench', 'admin_dashboard'];
            const needsFetch = forceListRefetch || operationalViews.includes(this.view);

            if (needsFetch) {
                 await this.fetchTickets();
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
                getOutsourcedCompany: (id) => this.getOutsourcedCompany(id),
                getOutsourcedPhone: (id) => this.getOutsourcedPhone(id),
                getTrackingLink: (t) => this.getTrackingLink(t),
                sendTrackingWhatsApp: () => this.sendTrackingWhatsApp(),
                sendCarrierWhatsApp: (t, c, tr) => this.sendCarrierWhatsApp(t, c, tr),
                validateTicketRequirements: (data) => this.validateTicketRequirements(data),
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
            return await window.AIDATicketActions.createTicket(this._getActionDeps());
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
        getCalendarTickets() {
            let source = this.tickets.filter(t => t.status !== 'Finalizado' && t.deadline);

            let effectiveFilter = this.adminDashboardFilters.technician;
            if (!this.hasRole('admin') && this.hasRole('tecnico')) {
                effectiveFilter = this.user.id;
            }

            if (effectiveFilter !== 'all' && effectiveFilter) {
                source = source.filter(t => t.technician_id === effectiveFilter);
            }

            if (!this.showAllCalendarTickets) {
                const techStatuses = ['Analise Tecnica', 'Andamento Reparo'];
                source = source.filter(t => techStatuses.includes(t.status));
            }
            return source;
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
        safeLogHTML(input) {
            if (!input) return '';
            // Convert \n to <br> before parsing to preserve line breaks
            const inputWithBreaks = input.replace(/\n/g, '<br>');

            const doc = new DOMParser().parseFromString(inputWithBreaks, 'text/html');
            const allowedTags = ['B', 'STRONG', 'BR'];

            const walk = (root) => {
                const children = Array.from(root.childNodes);
                for (const child of children) {
                    if (child.nodeType === Node.ELEMENT_NODE) {
                        const tagName = child.tagName.toUpperCase();
                        if (allowedTags.includes(tagName)) {
                            // Allowed: strip attributes, recurse
                            while (child.attributes.length > 0) {
                                child.removeAttribute(child.attributes[0].name);
                            }
                            walk(child);
                        } else {
                            // Disallowed: Unwrap (replace element with its children)
                            const fragment = document.createDocumentFragment();
                            while (child.firstChild) {
                                fragment.appendChild(child.firstChild);
                            }
                            // Process the moved children (now in fragment)
                            walk(fragment);
                            child.parentNode.replaceChild(fragment, child);
                        }
                    }
                }
            };

            walk(doc.body);
            return doc.body.innerHTML;
        },

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
            if (!ticket) return { client: '<b>Cliente</b>', device: '<b>Aparelho</b>' };

            const safeClientName = this.escapeHtml(ticket.client_name);
            const safeOsNumber = this.escapeHtml(ticket.os_number);
            const safeDevice = this.escapeHtml(ticket.device_model);

            let client = `<b>${safeClientName} da OS ${safeOsNumber}</b>`;
            const device = `<b>${safeDevice}</b>`;

            // Add outsourced context if applicable as requested by user
            if (ticket.is_outsourced && ticket.outsourced_company_id) {
                const company = this.escapeHtml(this.getOutsourcedCompany(ticket.outsourced_company_id));
                client += ` (Terceirizado: <b>${company}</b>)`;
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
            const visibleSteps = this.trackerConfig.visible_stages.length > 0
                ? this.trackerConfig.visible_stages
                : this.STATUS_COLUMNS;

            // If status is visible, show it
            if (visibleSteps.includes(currentStatus)) {
                return currentStatus;
            }

            // If hidden, find previous visible
            const actualIdx = this.STATUS_COLUMNS.indexOf(currentStatus);
            if (actualIdx === -1) return currentStatus;

            for (let i = actualIdx - 1; i >= 0; i--) {
                if (visibleSteps.includes(this.STATUS_COLUMNS[i])) {
                    return this.STATUS_COLUMNS[i];
                }
            }

            // Fallback
            return visibleSteps[0] || 'Aberto';
        },

        getPreviewProgressPercent() {
            const displayed = this.getPreviewDisplayedStatus();
            const visibleSteps = this.trackerConfig.visible_stages.length > 0
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
            this.fetchTickets();
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
                    const pOrder = { 'Urgente': 0, 'Alta': 1, 'Normal': 2, 'Baixa': 3 };
                    return pOrder[a.priority] - pOrder[b.priority];
                }
                if (sortMode === 'os') {
                    return a.os_number.localeCompare(b.os_number, undefined, { numeric: true });
                }
                if (sortMode === 'model') {
                    return a.device_model.localeCompare(b.device_model);
                }

                // Default Sort
                if (status === 'Aberto' || status === 'Analise Tecnica') {
                    // Primary: Analysis Deadline
                    if (a.analysis_deadline && !b.analysis_deadline) return -1;
                    if (!a.analysis_deadline && b.analysis_deadline) return 1;
                    if (a.analysis_deadline && b.analysis_deadline) {
                        const diff = new Date(a.analysis_deadline) - new Date(b.analysis_deadline);
                        if (diff !== 0) return diff;
                    }
                    // Secondary: Delivery Deadline
                    if (a.deadline && !b.deadline) return -1;
                    if (!a.deadline && b.deadline) return 1;
                    if (a.deadline && b.deadline) return new Date(a.deadline) - new Date(b.deadline);

                    return 0;
                } else {
                    // Others: Deadline -> Created
                    if (a.deadline && !b.deadline) return -1;
                    if (!a.deadline && b.deadline) return 1;
                    if (a.deadline && b.deadline) {
                        const diff = new Date(a.deadline) - new Date(b.deadline);
                        if (diff !== 0) return diff;
                    }
                    return new Date(a.created_at) - new Date(b.created_at);
                }
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
                if (!ticket.priority_requested) return false;
            }
            if (this.activeQuickFilter === 'delayed') {
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
