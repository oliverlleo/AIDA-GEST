
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
            ]
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

        // Forms
        loginForm: { company_code: '', username: '', password: '' },
        adminForm: { email: '', password: '' },
        registerForm: { companyName: '', email: '', password: '' },
        employeeForm: { name: '', username: '', password: '', roles: [] },

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

        // Selected Ticket
        selectedTicket: null,
        ticketLogs: [],
        dashboardLogs: [],
        logViewMode: 'timeline',
        modalSource: '',
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
        showFinalized: true,

        // Time
        currentTime: new Date(),

        // Modals
        modals: { newEmployee: false, editEmployee: false, ticket: false, viewTicket: false, outcome: false, logs: false, calendar: false, notifications: false, recycleBin: false, logistics: false, outsourced: false },

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
            'Aberto': 'Aberto', 'Terceirizado': 'Terceirizado',
            'Terceirizado': 'Terceirizado',
            'Analise Tecnica': 'Análise Técnica',
            'Aprovacao': 'Aprovação',
            'Compra Peca': 'Compra de Peças',
            'Andamento Reparo': 'Em Reparo',
            'Teste Final': 'Testes Finais',
            'Retirada Cliente': 'Retirada de Cliente',
            'Finalizado': 'Finalizado'
        },

        // --- HELPER: NATIVE FETCH (Stateless) ---
        async supabaseFetch(endpoint, method = 'GET', body = null) {
            const isRpc = endpoint.startsWith('rpc/');
            const url = `${SUPABASE_URL}/rest/v1/${endpoint}`;

            let token = SUPABASE_KEY;
            if (this.session && this.session.access_token) {
                token = this.session.access_token;
            }

            const headers = {
                'apikey': SUPABASE_KEY,
                'Authorization': `Bearer ${token}`,
                'Content-Type': 'application/json',
                'Prefer': method === 'GET' ? undefined : 'return=representation'
            };

            if (this.user && this.user.workspace_id) {
                headers['x-workspace-id'] = this.user.workspace_id;
            }

            const options = {
                method,
                headers,
                body: body ? JSON.stringify(body) : undefined
            };

            const response = await fetch(url, options);

            if (!response.ok) {
                const errorData = await response.json().catch(() => ({ message: response.statusText }));
                throw new Error(errorData.message || `Error ${response.status}: ${response.statusText}`);
            }

            if (response.status === 204) return null;

            return await response.json();
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
                            if (this.employeeSession.employee_id && !this.employeeSession.id) {
                                this.employeeSession.id = this.employeeSession.employee_id;
                            }
                            this.user = this.employeeSession;
                            if (this.employeeSession.workspace_name) this.workspaceName = this.employeeSession.workspace_name;
                            if (this.employeeSession.company_code) this.companyCode = this.employeeSession.company_code;
                            await this.fetchEmployees();
                            this.initTechFilter();
                        } catch (e) {
                            localStorage.removeItem('techassist_employee');
                        }
                    }
                }

                if (this.user) {
                    this.initTechFilter();
                    await this.fetchTickets();
                    await this.fetchTemplates();
                    await this.fetchDeviceModels();
                    await this.fetchDefectOptions();
                    await this.fetchOutsourcedCompanies();
                    this.fetchGlobalLogs();
                    this.setupRealtime();
                    if (this.view === 'dashboard') this.requestDashboardMetrics({ reason: 'init' });
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
                if (value === 'kanban') {
                    // Reset to Kanban mode (Active only)
                    this.fetchTickets();
                    setTimeout(() => this.initKanbanScroll(), 100);
                } else if (value === 'dashboard') {
                    // Dashboard/History mode
                    this.fetchTickets();
                    this.fetchGlobalLogs();
                    this.calculateMetrics();
                } else {
                    // Other views (e.g. tech_orders)
                    this.clearFilters();
                    this.fetchTickets();
                }
            });

            this.$watch('searchQuery', () => {
                this.handleSearchInput();
            });

            this.$watch('adminDashboardFilters', () => {
                // If filters change, reload dashboard metrics AND list
                this.requestDashboardMetrics({ reason: 'filters' });
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
            const params = {
                p_date_start: f.dateStart || null,
                p_date_end: f.dateEnd || null,
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
            // - If reason is realtime: ALWAYS fetch (unless throttled above)
            // - If not realtime: Check params match AND strict cache TTL (e.g. 5s) to avoid unnecessary re-fetches
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

                    const data = await this.supabaseFetch('rpc/get_dashboard_kpis', 'POST', params);
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
                    console.error("Dashboard RPC Error:", e);
                    this.notify("Erro ao carregar métricas.", "error");
                } finally {
                    this.dashboardMetricsPromise = null;

                    // If a realtime update came in while we were busy, trigger a new fetch now
                    if (this.pendingRealtimeRefresh) {
                        this.pendingRealtimeRefresh = false;
                        // Trigger immediate check (will be subject to throttle logic inside if applicable)
                        // If reason is 'realtime', it respects throttling.
                        // We assume lastDashboardCallTime was JUST updated above (if success).
                        // So a direct call might be throttled.
                        // However, if we just updated, maybe we don't *need* to fetch again?
                        // Actually, if an event happened *during* the fetch, the data we just got *might* be stale.
                        // But the throttle will block it anyway if < 1.5s.
                        // So this effectively queues it for "in 1.5s".
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

        // --- AUTH ---
        async loginAdmin() {
            this.loading = true;
            try {
                const { error } = await supabaseClient.auth.signInWithPassword({
                    email: this.adminForm.email,
                    password: this.adminForm.password,
                });
                if (error) this.notify(error.message, 'error');
            } finally {
                this.loading = false;
            }
        },
        async registerAdmin() {
            this.loading = true;
            try {
                const { data: authData, error: authError } = await supabaseClient.auth.signUp({
                    email: this.registerForm.email,
                    password: this.registerForm.password,
                });
                if (authError) return this.notify(authError.message, 'error');
                if (authData.user && !authData.session) return this.notify('Verifique seu e-mail.', 'success');
            } finally {
                this.loading = false;
            }
        },

        async completeCompanySetup() {
             this.loading = true;
             try {
                 if (!this.registerForm.companyName) return this.notify('Digite o nome da empresa.', 'error');
                 const generatedCode = Math.floor(1000 + Math.random() * 9000).toString();

                 const wsId = await this.supabaseFetch('rpc/create_owner_workspace_and_profile', 'POST', {
                        p_name: this.registerForm.companyName,
                        p_company_code: generatedCode
                 });

                this.newCompanyCode = generatedCode;
                this.registrationSuccess = true;
                this.notify('Conta criada!', 'success');
             } catch (err) {
                 console.error(err);
                 this.notify('Erro: ' + err.message, 'error');
             } finally {
                 this.loading = false;
             }
        },

        async loginEmployee() {
            this.loading = true;
            try {
                const data = await this.supabaseFetch('rpc/employee_login', 'POST', {
                        p_company_code: this.loginForm.company_code,
                        p_username: this.loginForm.username,
                        p_password: this.loginForm.password
                });

                if (data && data.length > 0) {
                    const emp = data[0];
                    if (emp.employee_id && !emp.id) {
                        emp.id = emp.employee_id;
                    }

                    this.employeeSession = emp;
                    this.user = emp;
                    this.workspaceName = emp.workspace_name;
                    this.companyCode = this.loginForm.company_code;

                    // Apply Global Config
                    if (emp.tracker_config) {
                        this.trackerConfig = {
                            ...this.trackerConfig,
                            ...emp.tracker_config,
                            colors: {
                                ...this.trackerConfig.colors,
                                ...(emp.tracker_config.colors || {})
                            }
                        };
                    }

                    localStorage.setItem('techassist_employee', JSON.stringify(emp));
                    this.notify('Bem-vindo, ' + emp.name, 'success');
                    await this.fetchEmployees();
                    this.initTechFilter();
                    await this.fetchTickets();
                    await this.fetchTemplates();
                    await this.fetchDeviceModels();
                    await this.fetchDefectOptions();
                    this.fetchGlobalLogs();

                    if (this.hasRole('tecnico') && !this.hasRole('admin') && !this.hasRole('atendente')) {
                        this.view = 'tech_orders';
                    }

                    this.setupRealtime();
                    if (this.view === 'dashboard') this.requestDashboardMetrics({ reason: 'login_employee' });
                } else {
                     this.notify('Credenciais inválidas.', 'error');
                }
            } catch(err) {
                 console.error(err);
                 this.notify('Falha no login: ' + err.message, 'error');
            } finally {
                this.loading = false;
            }
        },

        async logout() {
            this.loading = true;
            try { if (this.session) await supabaseClient.auth.signOut(); } catch (e) {}
            this.employeeSession = null;
            this.user = null;
            this.session = null;
            this.notificationsList = [];
            localStorage.removeItem('techassist_employee');
            this.view = 'dashboard';
            this.loading = false;
            window.location.reload();
        },
        async loadAdminData() {
            if (!this.session) return;
            const user = this.session.user;
            const key = user.id;

            if (this.loadedToken === key) {
                console.log('[Auth] Skipping loadAdminData - already loaded for', key);
                return;
            }

            console.log('[Auth] loadAdminData start...', key);

            try {
                // Modified select to include tracker_config
                const profileData = await this.supabaseFetch(`profiles?select=*,workspaces(name,company_code,whatsapp_number,tracker_config)&id=eq.${user.id}`);
                let profile = profileData && profileData.length > 0 ? profileData[0] : null;

                if (!profile) {
                    const wsData = await this.supabaseFetch(`workspaces?select=id,name,company_code,whatsapp_number&owner_id=eq.${user.id}`);
                    const workspace = wsData && wsData.length > 0 ? wsData[0] : null;

                    if (workspace) {
                        await this.supabaseFetch('profiles', 'POST', { id: user.id, workspace_id: workspace.id, role: 'admin' });
                        const newProfileData = await this.supabaseFetch(`profiles?select=*,workspaces(name,company_code,whatsapp_number,tracker_config)&id=eq.${user.id}`);
                        profile = newProfileData[0];
                    } else {
                        this.view = 'setup_required';
                        return;
                    }
                }

                if (profile) {
                    this.user = { id: user.id, email: user.email, name: 'Administrador', roles: ['admin'], workspace_id: profile.workspace_id };
                    this.workspaceName = profile.workspaces?.name;
                    this.companyCode = profile.workspaces?.company_code;
                    this.whatsappNumber = profile.workspaces?.whatsapp_number || '';

                    // Populate Tracker Config
                    if (profile.workspaces?.tracker_config) {
                        // Merge with defaults to ensure all fields exist
                        this.trackerConfig = {
                            ...this.trackerConfig,
                            ...profile.workspaces.tracker_config,
                            colors: {
                                ...this.trackerConfig.colors,
                                ...(profile.workspaces.tracker_config.colors || {})
                            }
                        };
                    }

                    await this.fetchEmployees();
                    this.initTechFilter();
                    await this.fetchTickets();
                    await this.fetchTemplates();
                    await this.fetchDeviceModels();
                    await this.fetchDefectOptions();
                    await this.fetchOutsourcedCompanies();
                    this.fetchGlobalLogs();
                    this.setupRealtime();
                    if (this.view === 'dashboard') this.requestDashboardMetrics({ reason: 'load_admin' });

                    this.loadedToken = key;
                }
            } catch (err) {
                console.error("Load Admin Error:", err);
            }
        },
        async fetchEmployees() {
            if (!this.user?.workspace_id) return;
            try {
                let data;
                if (this.session) {
                     data = await this.supabaseFetch(`employees?select=*&workspace_id=eq.${this.user.workspace_id}&deleted_at=is.null&order=created_at.desc`);
                } else {
                     data = await this.supabaseFetch('rpc/get_employees_for_workspace', 'POST', { p_workspace_id: this.user.workspace_id });
                }
                if (data) this.employees = data;
            } catch (e) {
                 console.error("Fetch Employees Error:", e);
            }
        },

        // --- COMPANY CONFIG ---
        async saveCompanyConfig() {
            if (!this.user?.workspace_id || !this.hasRole('admin')) return;
            this.loading = true;
            try {
                await this.supabaseFetch(`workspaces?id=eq.${this.user.workspace_id}`, 'PATCH', {
                    whatsapp_number: this.whatsappNumber
                });
                this.notify("Configurações salvas!");
            } catch (e) {
                this.notify("Erro ao salvar: " + e.message, "error");
            } finally {
                this.loading = false;
            }
        },

        // --- TRACKER CONFIG ACTIONS (NEW) ---
        async saveTrackerConfig() {
            if (!this.user?.workspace_id || !this.hasRole('admin')) return;
            this.loading = true;
            try {
                const res = await this.supabaseFetch(`workspaces?id=eq.${this.user.workspace_id}`, 'PATCH', {
                    tracker_config: this.trackerConfig
                });

                // Check if update actually happened
                if (Array.isArray(res) && res.length === 0) {
                    throw new Error("Permissão negada ou workspace não encontrado.");
                }

                if (this.view === 'management_settings') {
                    this.notify("Configurações de Gerenciamento salvas!");
                } else {
                    this.notify("Configurações de Acompanhamento salvas!");
                }

                // Refresh data to apply new flow rules (e.g. Tech Bench tickets)
                await this.fetchTickets();
            } catch (e) {
                this.notify("Erro ao salvar: " + e.message, "error");
            } finally {
                this.loading = false;
            }
        },

        async handleLogoUpload(event) {
            const file = event.target.files[0];
            if (!file) return;

            this.loading = true;
            try {
                const path = `${this.user.workspace_id}/logo/logo_${Date.now()}.png`; // Unique name to force refresh
                const url = `${SUPABASE_URL}/storage/v1/object/ticket_photos/${path}`;

                let token = this.session?.access_token || SUPABASE_KEY;
                const headers = {
                    'apikey': SUPABASE_KEY,
                    'Authorization': `Bearer ${token}`,
                    'x-workspace-id': this.user.workspace_id,
                    'Content-Type': file.type
                };

                const response = await fetch(url, { method: 'POST', headers, body: file });
                if (!response.ok) throw new Error("Falha no upload");

                // Construct Public URL
                const publicUrl = `${SUPABASE_URL}/storage/v1/object/public/ticket_photos/${path}`;
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
            try {
                await this.supabaseFetch('ticket_logs', 'POST', {
                    ticket_id: ticketId,
                    action: action,
                    details: details,
                    user_name: this.user.name
                });
                if (this.view === 'dashboard') this.fetchGlobalLogs();
            } catch (e) {
                console.error("Log failed:", e);
            }
        },

        async fetchTicketLogs(ticketId) {
            if (!this.hasRole('admin')) return [];
            try {
                const logs = await this.supabaseFetch(`ticket_logs?ticket_id=eq.${ticketId}&order=created_at.desc`);
                return logs || [];
            } catch (e) {
                console.error("Fetch logs failed:", e);
                return [];
            }
        },

        async fetchGlobalLogs() {
            if (!this.user?.workspace_id) return;
            try {
                const logs = await this.supabaseFetch(`ticket_logs?select=*,tickets(os_number,client_name,device_model)&order=created_at.desc&limit=10`);
                this.dashboardLogs = logs || [];
            } catch (e) {
                console.error("Fetch global logs failed:", e);
            }
        },

        // --- NOTIFICATIONS ---
        async fetchNotifications() {
            if (!this.user) return;
            try {
                let query = `notifications?select=*,tickets(os_number,device_model)&order=created_at.desc&limit=50`;
                const data = await this.supabaseFetch(query);

                if (data) {
                    const myRoles = this.user.roles || [];
                    const userId = this.user.id;

                    this.notificationsList = data.filter(n => {
                        if (n.recipient_user_id) return n.recipient_user_id === userId;
                        if (n.recipient_role) return myRoles.includes(n.recipient_role);
                        return false;
                    });
                }
            } catch(e) {
                console.error("Fetch Notif Error:", e);
            }
        },

        async createNotification(data) {
            try {
                await this.supabaseFetch('notifications', 'POST', data);
            } catch(e) { console.error("Create Notif Error:", e); }
        },

        async markNotificationRead(id) {
            try {
                const n = this.notificationsList.find(x => x.id === id);
                if (n) n.is_read = true;

                await this.supabaseFetch(`notifications?id=eq.${id}`, 'PATCH', { is_read: true, read_at: new Date().toISOString() });
            } catch(e) { console.error(e); }
        },

        async markAllRead() {
            const unreadIds = this.notificationsList.filter(n => !n.is_read).map(n => n.id);
            if (unreadIds.length === 0) return;

            this.notificationsList.forEach(n => n.is_read = true);
            await this.supabaseFetch(`notifications?id=in.(${unreadIds.join(',')})`, 'PATCH', { is_read: true, read_at: new Date().toISOString() });
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

        // --- TICKET LOGIC ---

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

            // 2. Optimized Dashboard Refresh (Throttle + Relevance Check)
            if (this.view === 'dashboard') {
                if (this.isRelevantUpdate(payload)) {
                    console.log('[Dashboard][Realtime] relevant event -> scheduling refresh');
                    this.invalidateDashboardCache('realtime_event');
                    this.requestDashboardMetrics({ reason: 'realtime' });
                }
            }

            // 3. Debounced List Refresh (Keep debounce for LIST only to avoid flicker)
            if (this.realtimeDebounceTimer) clearTimeout(this.realtimeDebounceTimer);

            this.realtimeDebounceTimer = setTimeout(async () => {
                // List Refresh Strategy
                if (payload.eventType === 'INSERT') {
                    if (this.ticketPagination.page === 0) {
                        await this.fetchTickets();
                    } else {
                        this.notify("Novos chamados disponíveis.", "info");
                    }
                } else if (payload.eventType === 'UPDATE') {
                    if (this.ticketPagination.page === 0) {
                        await this.fetchTickets();
                    } else {
                        const idx = this.tickets.findIndex(t => t.id === payload.new.id);
                        if (idx > -1) {
                            if (payload.new.deleted_at) {
                                this.tickets.splice(idx, 1);
                            } else {
                                this.tickets[idx] = { ...this.tickets[idx], ...payload.new };
                            }
                        }
                    }
                }
            }, 2000);
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

        async fetchTickets(loadMore = false) {
            if (!this.user?.workspace_id) return;

            this.ticketPagination.isLoading = true;

            if (loadMore) {
                this.ticketPagination.page++;
            } else {
                this.ticketPagination.page = 0;
                this.ticketPagination.hasMore = true;
                if (!loadMore) this.tickets = [];
            }

            try {
                // Base Endpoint with Workspace Filter
                let endpoint = `tickets?select=*&workspace_id=eq.${this.user.workspace_id}&deleted_at=is.null`;

                // SEARCH
                if (this.searchQuery) {
                    const q = this.searchQuery;
                    const qSafe = encodeURIComponent(`*${q}*`);
                    endpoint += `&or=(client_name.ilike.${qSafe},os_number.ilike.${qSafe},device_model.ilike.${qSafe},serial_number.ilike.${qSafe},contact_info.ilike.${qSafe})`;
                }

                // VIEW SPECIFIC LOGIC
                if (this.view === 'kanban' && !this.searchQuery) {
                    // Kanban: Active Only
                    // Definition: Not Delivered (delivered_at IS NULL)
                    endpoint += `&delivered_at=is.null`;
                    endpoint += `&order=created_at.desc`;
                    endpoint += `&limit=200`; // Hard limit for DOM safety
                } else if (this.view === 'tech_orders') {
                    // Tech View
                    if (this.hasRole('admin')) {
                        const techId = this.adminDashboardFilters.technician;
                        if (techId && techId !== 'all') {
                            endpoint += `&technician_id=eq.${techId}`;
                        }
                    } else if (this.user?.id) {
                         endpoint += `&or=(technician_id.eq.${this.user.id},technician_id.is.null)`;
                    }
                    endpoint += `&status=in.(Analise Tecnica,Andamento Reparo)`;
                    endpoint += `&order=created_at.asc`;
                } else {
                    // Dashboard/History/List: Apply Filters & Pagination
                    const f = this.adminDashboardFilters;

                    if (f.dateStart) endpoint += `&created_at=gte.${f.dateStart}T00:00:00`;
                    if (f.dateEnd) endpoint += `&created_at=lte.${f.dateEnd}T23:59:59`;
                    if (f.technician !== 'all') endpoint += `&technician_id=eq.${f.technician}`;
                    if (f.status !== 'all') endpoint += `&status=eq.${f.status}`;
                    if (f.defect !== 'all') endpoint += `&defect_reported=ilike.*${encodeURIComponent(f.defect)}*`;
                    if (f.deviceModel !== 'all') endpoint += `&device_model=eq.${encodeURIComponent(f.deviceModel)}`;

                    endpoint += `&order=created_at.desc`;

                    // PAGINATION
                    const limit = this.ticketPagination.limit;
                    const offset = this.ticketPagination.page * limit;
                    endpoint += `&limit=${limit}&offset=${offset}`;
                }

                const data = await this.supabaseFetch(endpoint);

                if (data) {
                    if (loadMore) {
                        this.tickets = [...this.tickets, ...data];
                    } else {
                        this.tickets = data;
                    }

                    // Check if we reached the end (for pagination)
                    if (data.length < this.ticketPagination.limit) {
                        this.ticketPagination.hasMore = false;
                    }

                    // POPULATE TECH TICKETS (Client Side Filter for safety/convenience)
                    if (this.view === 'tech_orders') {
                        this.techTickets = this.tickets;
                    } else {
                        // For other views, we maintain client-side derivation for consistency
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
                            const pOrder = { 'Urgente': 0, 'Alta': 1, 'Normal': 2, 'Baixa': 3 };
                            const pDiff = pOrder[a.priority] - pOrder[b.priority];
                            if (pDiff !== 0) return pDiff;
                            return new Date(a.deadline || 0) - new Date(b.deadline || 0);
                        });
                    }

                    if (!loadMore) {
                        await this.fetchOperationalAlerts();
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
             if (!this.user?.workspace_id) return;
             try {
                 const data = await this.supabaseFetch('checklist_templates?select=*');
                 if (data) {
                     this.checklistTemplates = data;
                     this.checklistTemplatesEntry = data.filter(t => !t.type || t.type === 'entry');
                     this.checklistTemplatesFinal = data.filter(t => t.type === 'final');
                 }
             } catch (e) {
                 console.error("Fetch Templates Error:", e);
             }
        },

        // --- DEVICE MODELS ---
        async fetchDeviceModels() {
            if (!this.user?.workspace_id) return;
            try {
                const data = await this.supabaseFetch(`device_models?select=*&workspace_id=eq.${this.user.workspace_id}&order=name.asc`);
                if (data) this.deviceModels = data;
            } catch(e) {
                console.error("Fetch Models Error:", e);
            }
        },
        async fetchDefectOptions() {
            if (!this.user?.workspace_id) return;
            try {
                const data = await this.supabaseFetch(`defect_options?select=*&workspace_id=eq.${this.user.workspace_id}&order=name.asc`);
                if (data) this.defectOptions = data;
            } catch(e) {
                console.error("Fetch Defect Options Error:", e);
            }
        },

        async fetchOutsourcedCompanies() {
            if (!this.user?.workspace_id) return;
            try {
                const data = await this.supabaseFetch(`outsourced_companies?select=*&workspace_id=eq.${this.user.workspace_id}&order=name.asc`);
                if (data) this.outsourcedCompanies = data;
            } catch(e) {
                console.error("Fetch Outsourced Companies Error:", e);
            }
        },

        async createOutsourcedCompany(name, phone) {
            if (!name || !name.trim()) return;
            if (!this.user?.workspace_id) return;

            try {
                await this.supabaseFetch('outsourced_companies', 'POST', {
                    workspace_id: this.user.workspace_id,
                    name: name.trim(),
                    phone: phone ? phone.trim() : null
                });
                await this.fetchOutsourcedCompanies();
                this.notify("Empresa parceira cadastrada!", "success");
            } catch(e) {
                this.notify("Erro ao cadastrar: " + e.message, "error");
            }
        },

        async deleteOutsourcedCompany(id) {
            if (!confirm("Excluir esta empresa parceira?")) return;
            try {
                await this.supabaseFetch(`outsourced_companies?id=eq.${id}`, 'DELETE');
                this.notify("Empresa excluída.");
                await this.fetchOutsourcedCompanies();
            } catch(e) {
                this.notify("Erro ao excluir: " + e.message, "error");
            }
        },

        async createDeviceModel(name) {
            if (!name || !name.trim()) return;
            if (!this.user?.workspace_id) return;

            if (this.deviceModels.some(m => m.name.toLowerCase() === name.trim().toLowerCase())) {
                return this.notify("Modelo já existe.", "error");
            }

            try {
                await this.supabaseFetch('device_models', 'POST', {
                    workspace_id: this.user.workspace_id,
                    name: name.trim()
                });
                await this.fetchDeviceModels();
                this.notify("Modelo cadastrado!", "success");
                return true;
            } catch(e) {
                this.notify("Erro ao salvar modelo: " + e.message, "error");
                return false;
            }
        },
        async createDefectOption(name) {
            if (!name || !name.trim()) return false;
            if (!this.user?.workspace_id) return false;

            const trimmed = name.trim();
            if (this.defectOptions.some(option => option.name.toLowerCase() === trimmed.toLowerCase())) {
                this.notify("Defeito já cadastrado.", "error");
                return false;
            }

            try {
                await this.supabaseFetch('defect_options', 'POST', {
                    workspace_id: this.user.workspace_id,
                    name: trimmed
                });
                this.notify("Defeito cadastrado!", "success");
                await this.fetchDefectOptions();
                return true;
            } catch(e) {
                this.notify("Erro ao salvar defeito: " + e.message, "error");
                return false;
            }
        },

        async deleteDeviceModel(id) {
            if (!confirm("Excluir este modelo da lista?")) return;
            try {
                await this.supabaseFetch(`device_models?id=eq.${id}`, 'DELETE');
                this.notify("Modelo excluído.");
                await this.fetchDeviceModels();
                if (this.ticketForm.model && !this.deviceModels.find(m => m.name === this.ticketForm.model)) {
                    this.ticketForm.model = '';
                }
            } catch(e) {
                this.notify("Erro ao excluir: " + e.message, "error");
            }
        },
        async deleteDefectOption(id) {
            if (!confirm("Excluir este defeito da lista?")) return;
            try {
                await this.supabaseFetch(`defect_options?id=eq.${id}`, 'DELETE');
                this.notify("Defeito excluído.");
                await this.fetchDefectOptions();
                const available = new Set(this.defectOptions.map(option => option.name));
                this.ticketForm.defects = (this.ticketForm.defects || []).filter(defect => available.has(defect));
            } catch(e) {
                this.notify("Erro ao excluir: " + e.message, "error");
            }
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
            if (!this.newTemplateName) return this.notify("Nomeie o modelo", "error");
            if (this.ticketForm.checklist.length === 0) return this.notify("Adicione itens", "error");

            try {
                await this.supabaseFetch('checklist_templates', 'POST', {
                    workspace_id: this.user.workspace_id,
                    name: this.newTemplateName,
                    items: this.ticketForm.checklist.map(i => i.item),
                    type: 'entry'
                });

                this.notify("Modelo salvo!");
                this.newTemplateName = '';
                this.fetchTemplates();
            } catch (error) {
                this.notify("Erro ao salvar: " + error.message, "error");
            }
        },

        async deleteTemplate() {
            if (!this.selectedTemplateId) return;
            if (!confirm("Tem certeza que deseja excluir este modelo?")) return;

            try {
                await this.supabaseFetch(`checklist_templates?id=eq.${this.selectedTemplateId}`, 'DELETE');

                this.notify("Modelo excluído.");
                this.selectedTemplateId = '';
                this.fetchTemplates();
            } catch (e) {
                this.notify("Erro ao excluir: " + e.message, "error");
            }
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
            if (!this.newTemplateNameFinal) return this.notify("Nomeie o modelo final", "error");
            if (this.ticketForm.checklist_final.length === 0) return this.notify("Adicione itens", "error");

            try {
                await this.supabaseFetch('checklist_templates', 'POST', {
                    workspace_id: this.user.workspace_id,
                    name: this.newTemplateNameFinal,
                    items: this.ticketForm.checklist_final.map(i => i.item),
                    type: 'final'
                });

                this.notify("Modelo final salvo!");
                this.newTemplateNameFinal = '';
                this.fetchTemplates();
            } catch (error) {
                this.notify("Erro ao salvar: " + error.message, "error");
            }
        },
        async deleteTemplateFinal() {
            if (!this.selectedTemplateIdFinal) return;
            if (!confirm("Tem certeza que deseja excluir este modelo?")) return;
            try {
                await this.supabaseFetch(`checklist_templates?id=eq.${this.selectedTemplateIdFinal}`, 'DELETE');
                this.notify("Modelo excluído.");
                this.selectedTemplateIdFinal = '';
                this.fetchTemplates();
            } catch (e) {
                this.notify("Erro: " + e.message, "error");
            }
        },
        loadTemplateFinal() {
            const tmpl = this.checklistTemplates.find(t => t.id === this.selectedTemplateIdFinal);
            if (tmpl) this.ticketForm.checklist_final = tmpl.items.map(s => ({ item: s, ok: false }));
        },

        async createTicket() {
             if (!this.ticketForm.client_name || !this.ticketForm.os_number || !this.ticketForm.model || !this.ticketForm.defects || this.ticketForm.defects.length === 0) {
                 return this.notify("Preencha os campos obrigatórios (*)", "error");
             }

             if (this.ticketForm.is_outsourced) {
                 if (!this.ticketForm.outsourced_company_id) return this.notify("Selecione a empresa parceira.", "error");
             } else {
                 if (!this.ticketForm.technician_id) return this.notify("Selecione um Técnico Responsável ou 'Todos'.", "error");
             }

             if (this.deviceModels && this.deviceModels.length > 0 && !this.deviceModels.find(m => m.name === this.ticketForm.model)) {
                 return this.notify("Modelo inválido. Cadastre-o no ícone + antes de salvar.", "error");
             }

             if (this.ticketForm.deadline && this.ticketForm.analysis_deadline) {
                 const deadline = new Date(this.ticketForm.deadline);
                 const analysis = new Date(this.ticketForm.analysis_deadline);
                 if (analysis > deadline) {
                     return this.notify("O Prazo de Análise não pode ser maior que o Prazo de Entrega.", "error");
                 }
             }

             this.loading = true;

             try {
                 let techId = this.ticketForm.technician_id;
                 if (techId === 'all') techId = null;

                 const ticketData = {
                     id: this.ticketForm.id,
                     workspace_id: this.user.workspace_id,
                    client_name: this.ticketForm.client_name,
                    os_number: this.ticketForm.os_number,
                    device_model: this.ticketForm.model,
                    serial_number: this.ticketForm.serial,
                    defect_reported: this.ticketForm.defects.length ? this.ticketForm.defects.join(', ') : null,
                    priority: this.ticketForm.priority,
                    contact_info: this.ticketForm.contact,
                     deadline: this.toUTC(this.ticketForm.deadline) || null,
                     analysis_deadline: this.toUTC(this.ticketForm.analysis_deadline) || null,
                     device_condition: this.ticketForm.device_condition,
                     technician_id: this.ticketForm.is_outsourced ? null : techId,
                     is_outsourced: this.ticketForm.is_outsourced,
                     outsourced_company_id: (this.ticketForm.is_outsourced && this.ticketForm.outsourced_company_id && this.ticketForm.outsourced_company_id !== '') ? this.ticketForm.outsourced_company_id : null,
                     checklist_data: this.ticketForm.checklist,
                     checklist_final_data: this.ticketForm.checklist_final,
                     photos_urls: this.ticketForm.photos,
                     status: 'Aberto',
                     created_by_name: this.user.name
                 };

                 const createdData = await this.supabaseFetch('tickets', 'POST', ticketData);
                 const createdTicket = createdData && createdData.length > 0 ? createdData[0] : ticketData;

                 const ctx = this.getLogContext(createdTicket);
                 await this.logTicketAction(createdTicket.id, 'Novo Chamado', `Um novo chamado foi criado para o ${ctx.device} de ${ctx.client}.`);

                 this.notify("Chamado criado!");
                 this.modals.ticket = false;
                 await this.fetchTickets();
             } catch (err) {
                 this.notify("Erro ao criar: " + err.message, "error");
             } finally {
                 this.loading = false;
             }
        },

        viewTicketDetails(ticket, source = 'kanban') {
            this.selectedTicket = ticket;
            this.modalSource = source;
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
            if (!this.selectedTicket) return;
            const formatForInput = (dateStr) => {
                if (!dateStr) return '';
                const d = new Date(dateStr);
                const pad = (n) => n < 10 ? '0' + n : n;
                return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
            };

            this.editDeadlineForm.deadline = formatForInput(this.selectedTicket.deadline);
            this.editDeadlineForm.analysis_deadline = formatForInput(this.selectedTicket.analysis_deadline);
            this.editingDeadlines = true;
        },

        cancelEditingDeadlines() {
            this.editingDeadlines = false;
            this.editDeadlineForm = { deadline: '', analysis_deadline: '' };
        },

        async saveDeadlines() {
            if (!this.selectedTicket) return;

            if (this.editDeadlineForm.deadline && this.editDeadlineForm.analysis_deadline) {
                const deadline = new Date(this.editDeadlineForm.deadline);
                const analysis = new Date(this.editDeadlineForm.analysis_deadline);
                if (analysis > deadline) {
                    return this.notify("O Prazo de Análise não pode ser maior que o Prazo de Entrega.", "error");
                }
            }

            this.loading = true;
            try {
                const oldDeadline = this.selectedTicket.deadline ? new Date(this.selectedTicket.deadline).toLocaleString() : 'Não definido';
                const newDeadline = this.editDeadlineForm.deadline ? new Date(this.editDeadlineForm.deadline).toLocaleString() : 'Não definido';

                const oldAnalysis = this.selectedTicket.analysis_deadline ? new Date(this.selectedTicket.analysis_deadline).toLocaleString() : 'Não definido';
                const newAnalysis = this.editDeadlineForm.analysis_deadline ? new Date(this.editDeadlineForm.analysis_deadline).toLocaleString() : 'Não definido';

                if (oldDeadline !== newDeadline) {
                    const ctx = this.getLogContext(this.selectedTicket);
                    await this.logTicketAction(
                        this.selectedTicket.id,
                        'Alterou Prazo',
                        `${this.user.name} alterou o prazo do ${ctx.device} de ${ctx.client} de ${oldDeadline} para ${newDeadline}`
                    );
                }

                if (oldAnalysis !== newAnalysis) {
                    const ctx = this.getLogContext(this.selectedTicket);
                    await this.logTicketAction(
                        this.selectedTicket.id,
                        'Alterou Prazo Análise',
                        `${this.user.name} alterou o prazo de análise do ${ctx.device} de ${ctx.client} de ${oldAnalysis} para ${newAnalysis}`
                    );
                }

                const updates = {
                    deadline: this.toUTC(this.editDeadlineForm.deadline) || null,
                    analysis_deadline: this.toUTC(this.editDeadlineForm.analysis_deadline) || null
                };

                await this.supabaseFetch(`tickets?id=eq.${this.selectedTicket.id}`, 'PATCH', updates);

                this.selectedTicket.deadline = updates.deadline;
                this.selectedTicket.analysis_deadline = updates.analysis_deadline;

                this.notify("Prazos atualizados!");
                this.editingDeadlines = false;
                await this.fetchTickets();
            } catch (e) {
                this.notify("Erro ao salvar prazos: " + e.message, "error");
            } finally {
                this.loading = false;
            }
        },

        async saveTicketChanges() {
             if (!this.selectedTicket) return;
             this.loading = true;
             try {
                 await this.supabaseFetch(`tickets?id=eq.${this.selectedTicket.id}`, 'PATCH', {
                     tech_notes: this.selectedTicket.tech_notes,
                     parts_needed: this.selectedTicket.parts_needed,
                     checklist_data: this.selectedTicket.checklist_data,
                     checklist_final_data: this.selectedTicket.checklist_final_data,
                     photos_urls: this.selectedTicket.photos_urls
                 });
                 this.notify("Alterações salvas!");
                 await this.fetchTickets();
             } catch (e) {
                 this.notify("Erro ao salvar: " + e.message, "error");
             } finally {
                 this.loading = false;
             }
        },

        async uploadTicketPhoto(file, ticketId) {
            if (!this.user?.workspace_id) return;
            this.loading = true;

            const fileName = `${Date.now()}_${file.name.replace(/[^a-zA-Z0-9.]/g, '')}`;
            const path = `${this.user.workspace_id}/${ticketId}/${fileName}`;
            const url = `${SUPABASE_URL}/storage/v1/object/ticket_photos/${path}`;

            try {
                let token = SUPABASE_KEY;
                if (this.session && this.session.access_token) {
                    token = this.session.access_token;
                }

                const headers = {
                    'apikey': SUPABASE_KEY,
                    'Authorization': `Bearer ${token}`,
                    'x-workspace-id': this.user.workspace_id,
                    'Content-Type': file.type
                };

                const response = await fetch(url, {
                    method: 'POST',
                    headers: headers,
                    body: file
                });

                if (!response.ok) {
                    const err = await response.json().catch(() => ({}));
                    throw new Error(err.message || 'Upload falhou');
                }

                const publicUrl = `${SUPABASE_URL}/storage/v1/object/public/ticket_photos/${path}`;
                return publicUrl;

            } catch (e) {
                console.error(e);
                this.notify("Erro upload: " + e.message, "error");
                return null;
            } finally {
                this.loading = false;
            }
        },

        async handlePhotoUpload(event, targetList = 'new') {
            const files = event.target.files;
            if (!files || files.length === 0) return;

            let ticketId;
            let targetArray;

            if (targetList === 'new') {
                ticketId = this.ticketForm.id;
                targetArray = this.ticketForm.photos;
            } else {
                ticketId = this.selectedTicket.id;
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
                 this.selectedTicket.photos_urls.splice(index, 1);
             }
        },

        // --- SHARE TICKET ---
        getTrackingLink(ticketId) {
            const baseUrl = window.location.origin + window.location.pathname.replace('index.html', '') + 'acompanhar.html';
            return `${baseUrl}?id=${ticketId}`;
        },

        openShareModal() {
            if (this.selectedTicket) {
                this.showShareModal = true;
            }
        },

        copyTrackingLink() {
             if (!this.selectedTicket) return;
             const link = this.getTrackingLink(this.selectedTicket.id);
             navigator.clipboard.writeText(link).then(() => {
                 this.notify("Link copiado!");
             });
        },

        sendTrackingWhatsApp() {
            if (!this.selectedTicket || !this.selectedTicket.contact_info) return this.notify("Sem contato cadastrado", "error");

            const link = this.getTrackingLink(this.selectedTicket.id);
            const msg = `Olá ${this.selectedTicket.client_name}, acompanhe o progresso do seu reparo em tempo real aqui: ${link}`;

            let number = this.selectedTicket.contact_info.replace(/\D/g, '');
            if (number.length <= 11) number = '55' + number;

            window.open(`https://wa.me/${number}?text=${encodeURIComponent(msg)}`, '_blank');
        },

        sendCarrierWhatsApp(ticket, carrier, trackingCode) {
            if (!ticket || !ticket.contact_info) return;

            const link = this.getTrackingLink(ticket.id);
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
            if (!this.user?.workspace_id) return;
            try {
                const data = await this.supabaseFetch(
                    `internal_notes?select=*&workspace_id=eq.${this.user.workspace_id}&ticket_id=eq.${ticketId}&order=created_at.asc`
                );
                this.internalNotes = data || [];
            } catch (e) {
                console.error("Fetch Internal Notes Error:", e);
            }
        },

        async fetchGeneralNotes() {
            if (!this.user?.workspace_id) return;
            try {
                let query = `internal_notes?select=*&workspace_id=eq.${this.user.workspace_id}&ticket_id=is.null&is_archived=eq.false`;

                if (!this.showResolvedNotes) {
                    query += `&is_resolved=eq.false`;
                }

                if (this.noteDateFilter) {
                    const start = new Date(this.noteDateFilter + 'T00:00:00').toISOString();
                    const end = new Date(this.noteDateFilter + 'T23:59:59').toISOString();
                    query += `&created_at=gte.${start}&created_at=lte.${end}`;
                }

                query += `&order=created_at.desc`;

                const data = await this.supabaseFetch(query);
                this.generalNotes = data || [];
            } catch (e) {
                console.error("Fetch General Notes Error:", e);
            }
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
            const text = isGeneral ? this.newGeneralNoteText : this.newNoteText;
            const isChecklist = isGeneral ? this.generalNoteIsChecklist : this.noteIsChecklist;
            const checklistItems = isGeneral ? this.generalNoteChecklistItems : this.noteChecklistItems;

            if (!text.trim() && (!isChecklist || checklistItems.length === 0)) return;

            this.loading = true;
            try {
                const mentionRegex = /@(\w+)/g;
                const matches = text.match(mentionRegex) || [];
                const mentions = matches.map(m => m.substring(1));

                const cleanChecklist = checklistItems
                    .filter(i => i.text.trim().length > 0)
                    .map(i => ({ item: i.text, ok: i.ok }));

                const payload = {
                    workspace_id: this.user.workspace_id,
                    ticket_id: ticketId,
                    author_id: this.user.id,
                    author_name: this.user.name,
                    content: text,
                    checklist_data: isChecklist ? cleanChecklist : [],
                    mentions: mentions,
                    is_resolved: false,
                    created_at: new Date().toISOString()
                };

                await this.supabaseFetch('internal_notes', 'POST', payload);

                if (isGeneral) {
                    this.newGeneralNoteText = '';
                    this.generalNoteIsChecklist = false;
                    this.generalNoteChecklistItems = [];
                    await this.fetchGeneralNotes();
                } else {
                    this.newNoteText = '';
                    this.noteIsChecklist = false;
                    this.noteChecklistItems = [];
                    if (ticketId) await this.fetchInternalNotes(ticketId);
                }
                this.showMentionList = false;

            } catch (e) {
                this.notify("Erro ao enviar nota: " + e.message, "error");
            } finally {
                this.loading = false;
            }
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
            note.checklist_data[itemIndex].ok = !note.checklist_data[itemIndex].ok;

            try {
                await this.supabaseFetch(`internal_notes?id=eq.${note.id}`, 'PATCH', {
                    checklist_data: note.checklist_data
                });
            } catch (e) {
                console.error("Error toggling checklist:", e);
                note.checklist_data[itemIndex].ok = !note.checklist_data[itemIndex].ok;
            }
        },

        async resolveNote(note) {
            const newStatus = !note.is_resolved;
            note.is_resolved = newStatus;

            try {
                await this.supabaseFetch(`internal_notes?id=eq.${note.id}`, 'PATCH', {
                    is_resolved: newStatus
                });
            } catch (e) {
                note.is_resolved = !newStatus;
                this.notify("Erro ao atualizar status", "error");
            }
        },

        async archiveNote(note) {
            if (!confirm("Arquivar esta nota?")) return;
            try {
                await this.supabaseFetch(`internal_notes?id=eq.${note.id}`, 'PATCH', {
                    is_archived: true,
                    archived_at: new Date().toISOString()
                });
                if (note.ticket_id) {
                    this.internalNotes = this.internalNotes.filter(n => n.id !== note.id);
                } else {
                    this.generalNotes = this.generalNotes.filter(n => n.id !== note.id);
                }
            } catch (e) {
                this.notify("Erro ao arquivar", "error");
            }
        },

        // --- WORKFLOW ACTIONS ---

        async updateStatus(ticket, newStatus, additionalUpdates = {}, actionLog = null) {
            this.loading = true;
            try {
                if (actionLog) {
                     await this.logTicketAction(ticket.id, actionLog.action, actionLog.details);
                }

                const updates = { status: newStatus, updated_at: new Date().toISOString(), ...additionalUpdates };

                await this.supabaseFetch(`tickets?id=eq.${ticket.id}`, 'PATCH', updates);

                this.notify("Status atualizado");
                await this.fetchTickets();
                this.modals.viewTicket = false;
            } catch (error) {
                console.error(error);
                this.notify("Erro ao atualizar: " + (error.message || error), "error");
            } finally {
                this.loading = false;
            }
        },

        async startAnalysis(ticket) {
            const ctx = this.getLogContext(ticket);
            await this.updateStatus(ticket, 'Analise Tecnica', {}, {
                action: 'Iniciou Atendimento',
                details: `${ctx.device} de ${ctx.client} enviado para análise do técnico.`
            });
        },

        async finishAnalysis() {
            if (this.analysisForm.needsParts && !this.analysisForm.partsList) {
                return this.notify("Liste as peças necessárias.", "error");
            }
            const ctx = this.getLogContext(this.selectedTicket);
            await this.updateStatus(this.selectedTicket, 'Aprovacao', {
                parts_needed: this.analysisForm.partsList,
                tech_notes: this.selectedTicket.tech_notes
            }, { action: 'Finalizou Análise', details: `${ctx.device} de ${ctx.client} enviado para fase de aprovação do cliente.` });
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
            this.openWhatsApp(ticket.contact_info);
        },

        async sendBudget(ticket = this.selectedTicket) {
            this.loading = true;
            try {
                const ctx = this.getLogContext(ticket);
                await this.logTicketAction(ticket.id, 'Enviou Orçamento', `Orçamento para o ${ctx.device} de ${ctx.client} foi enviado para o cliente.`);

                await this.supabaseFetch(`tickets?id=eq.${ticket.id}`, 'PATCH', {
                    budget_status: 'Enviado',
                    budget_sent_at: new Date().toISOString()
                });

                const link = this.getTrackingLink(ticket.id);
                const msg = `Olá ${ticket.client_name}, seu orçamento está pronto. Acompanhe aqui: ${link}`;

                let number = ticket.contact_info.replace(/\D/g, '');
                if (number.length <= 11) number = '55' + number;
                window.open(`https://wa.me/${number}?text=${encodeURIComponent(msg)}`, '_blank');

                if (this.selectedTicket && this.selectedTicket.id === ticket.id) {
                    this.selectedTicket = { ...this.selectedTicket, budget_status: 'Enviado' };
                }
                this.notify("Orçamento marcado como Enviado (WhatsApp aberto).");
                await this.fetchTickets();
            } catch(e) {
                 this.notify("Erro: " + e.message, "error");
            } finally {
                this.loading = false;
            }
        },
        async approveRepair(ticket = this.selectedTicket) {
            const nextStatus = ticket.parts_needed ? 'Compra Peca' : 'Andamento Reparo';
            const ctx = this.getLogContext(ticket);
            await this.updateStatus(ticket, nextStatus, { budget_status: 'Aprovado' }, { action: 'Aprovou Orçamento', details: `${ctx.client} aprovou o orçamento do ${ctx.device}.` });
        },
        async denyRepair(ticket = this.selectedTicket) {
             const ctx = this.getLogContext(ticket);
             await this.updateStatus(ticket, 'Retirada Cliente', { budget_status: 'Negado', repair_successful: false }, { action: 'Negou Orçamento', details: `${ctx.client} reprovou o orçamento do ${ctx.device}.` });
        },

        async markPurchased(ticket = this.selectedTicket) {
             this.loading = true;
             try {
                 const ctx = this.getLogContext(ticket);
                 const rawPart = ticket.parts_needed || 'peça';
                 const part = `<span class="text-brand-500 font-bold">${this.escapeHtml(rawPart)}</span>`;
                 await this.logTicketAction(ticket.id, 'Confirmou Compra', `Compra da peça '${part}' para o ${ctx.device} de ${ctx.client} foi realizada.`);

                 await this.supabaseFetch(`tickets?id=eq.${ticket.id}`, 'PATCH', {
                    parts_status: 'Comprado',
                    parts_purchased_at: new Date().toISOString()
                });
                await this.fetchTickets();
             } catch(e) {
                 this.notify("Erro: " + e.message, "error");
             } finally {
                this.loading = false;
             }
        },
        async confirmReceived(ticket = this.selectedTicket) {
             const ctx = this.getLogContext(ticket);
             const rawPart = ticket.parts_needed || 'peça';
             const part = `<span class="text-brand-500 font-bold">${this.escapeHtml(rawPart)}</span>`;
             await this.updateStatus(ticket, 'Andamento Reparo', {
                 parts_status: 'Recebido',
                 parts_received_at: new Date().toISOString()
             }, { action: 'Recebeu Peças', details: `Peça ${part} recebida para o ${ctx.device} de ${ctx.client}. Reparo liberado.` });
        },

        async startRepair(ticket = this.selectedTicket) {
             this.loading = true;
             try {
                 const ctx = this.getLogContext(ticket);
                 await this.logTicketAction(ticket.id, 'Iniciou Execução', `Reparo iniciado do ${ctx.device} de ${ctx.client}.`);

                 const now = new Date().toISOString();
                 await this.supabaseFetch(`tickets?id=eq.${ticket.id}`, 'PATCH', {
                    repair_start_at: now
                });

                if (this.selectedTicket && this.selectedTicket.id === ticket.id) {
                    this.selectedTicket = { ...this.selectedTicket, repair_start_at: now };
                }
                await this.fetchTickets();
             } catch(e) {
                 this.notify("Erro: " + e.message, "error");
             } finally {
                 this.loading = false;
             }
        },

        openOutcomeModal(mode, ticket = this.selectedTicket) {
            this.selectedTicket = ticket;
            this.outcomeMode = mode;
            this.showTestFailureForm = false;
            this.modals.outcome = true;
        },

        async finishRepair(success) {
            const ticket = this.selectedTicket;
            const nextStatus = success ? 'Teste Final' : 'Retirada Cliente';
            const updates = {
                repair_successful: success,
                repair_end_at: new Date().toISOString()
            };

            // Calculate Duration
            const duration = this.getDuration(ticket.repair_start_at);
            const ctx = this.getLogContext(ticket);

            const detailMsg = success
                ? `O reparo do ${ctx.device} de ${ctx.client} foi finalizado com sucesso.`
                : `O ${ctx.device} de ${ctx.client} não teve reparo.`;

            this.modals.outcome = false;
            await this.updateStatus(ticket, nextStatus, updates, {
                action: 'Finalizou Reparo',
                details: detailMsg
            });
        },

        async startTest(ticket = this.selectedTicket) {
             this.loading = true;
             try {
                 const ctx = this.getLogContext(ticket);
                 await this.logTicketAction(ticket.id, 'Iniciou Testes', `Os testes no ${ctx.device} de ${ctx.client} foram iniciados.`);

                 const now = new Date().toISOString();
                 await this.supabaseFetch(`tickets?id=eq.${ticket.id}`, 'PATCH', {
                    test_start_at: now
                });

                if (this.selectedTicket && this.selectedTicket.id === ticket.id) {
                    this.selectedTicket = { ...this.selectedTicket, test_start_at: now };
                }

                await this.fetchTickets();
             } catch(e) {
                 this.notify("Erro: " + e.message, "error");
             } finally {
                this.loading = false;
             }
        },

        async concludeTest(success) {
            const ticket = this.selectedTicket;
            const ctx = this.getLogContext(ticket);

            if (success) {
                this.modals.outcome = false;
                // Redirect logic based on Logistics Mode
                // If standard mode, it goes to "Retirada Cliente" which matches current DB/UI logic.
                await this.updateStatus(ticket, 'Retirada Cliente', {}, { action: 'Concluiu Testes', details: `O ${ctx.device} de ${ctx.client} foi aprovado.` });
            } else {
                // FAILURE LOGIC
                if (!this.testFailureData.reason) return this.notify("Descreva o defeito apresentado", "error");

                // Outsourced Flow Logic
                if (ticket.is_outsourced) {
                     if (!this.testFailureData.action) return this.notify("Selecione a ação (Devolver ou Reparo)", "error");

                     if (this.testFailureData.action === 'return') {
                         if (!this.testFailureData.newDeadline) return this.notify("Defina um novo prazo", "error");

                         const count = (ticket.outsourced_return_count || 0) + 1;
                         const companyName = this.getOutsourcedCompany(ticket.outsourced_company_id);

                         // Add note to history
                         const newNote = {
                             date: new Date().toISOString(),
                             text: this.testFailureData.reason,
                             user: this.user.name,
                             context: `Retorno ${count}x`
                         };
                         const updatedNotes = [...(ticket.outsourced_notes || []), newNote];

                         this.modals.outcome = false;
                         await this.updateStatus(ticket, 'Terceirizado', {
                             outsourced_deadline: this.toUTC(this.testFailureData.newDeadline),
                             outsourced_return_count: count,
                             test_start_at: null,
                             outsourced_notes: updatedNotes
                         }, {
                             action: 'Devolveu para Terceiro',
                             details: `${ctx.device} retornado para ${companyName} (${count}ª vez). Motivo: ${this.testFailureData.reason}`
                         });
                         return;
                     }
                }

                if (!this.testFailureData.newDeadline) return this.notify("Defina um novo prazo", "error");

                const newNote = {
                    date: new Date().toISOString(),
                    text: this.testFailureData.reason,
                    user: this.user.name,
                    context: ticket.is_outsourced && this.testFailureData.action === 'repair' ? 'Falha de Terceiro' : 'Reprova em Teste'
                };

                const existingNotes = Array.isArray(ticket.test_notes) ? ticket.test_notes : [];
                const updatedNotes = [...existingNotes, newNote];

                this.modals.outcome = false;
                await this.updateStatus(ticket, 'Andamento Reparo', {
                    deadline: this.toUTC(this.testFailureData.newDeadline),
                    priority: this.testFailureData.newPriority,
                    repair_start_at: null,
                    test_start_at: null,
                    status: 'Andamento Reparo',
                    test_notes: updatedNotes
                }, { action: 'Reprovou Testes', details: 'Retornado para Reparo. Defeito: ' + this.testFailureData.reason });
                this.notify("Retornado para reparo com urgência!");
            }
        },

        // --- OUTSOURCED FUNCTIONS ---
        getOutsourcedCompany(id) {
             const c = this.outsourcedCompanies.find(x => x.id === id);
             return c ? c.name : 'Desconhecido';
        },
        getOutsourcedPhone(id) {
             const c = this.outsourcedCompanies.find(x => x.id === id);
             return c ? c.phone : '';
        },

        openOutsourcedModal(ticket) {
            this.selectedTicket = ticket;
            this.outsourcedForm = { company_id: ticket.outsourced_company_id, deadline: '', price: '' };
            this.modals.outsourced = true;
        },

        async sendToOutsourced() {
             if (!this.outsourcedForm.deadline) return this.notify("Informe o prazo.", "error");

             this.loading = true;
             try {
                 const ticket = this.selectedTicket;
                 const ctx = this.getLogContext(ticket);
                 const companyName = this.getOutsourcedCompany(ticket.outsourced_company_id);

                 await this.updateStatus(ticket, 'Terceirizado', {
                     outsourced_deadline: this.toUTC(this.outsourcedForm.deadline),
                     // If moving from Aberto, ensure analysis logic is skipped or marked as handled externally
                     status: 'Terceirizado'
                 }, {
                     action: 'Enviou Terceirizado',
                     details: `${ctx.device} de ${ctx.client} enviado para ${companyName}. Prazo: ${new Date(this.outsourcedForm.deadline).toLocaleDateString('pt-BR')}.`
                 });

                 this.modals.outsourced = false;
                 this.modals.viewTicket = false; // Close detail view if open
             } catch(e) {
                 this.notify("Erro: " + e.message, "error");
                 this.loading = false;
             }
        },

        async receiveFromOutsourced(ticket) {
             // For this specific action, we don't want the (Terceirizado: X) suffix in the context
             // because the log message already says "recebido da X".
             const safeClientName = this.escapeHtml(ticket.client_name);
             const safeOsNumber = this.escapeHtml(ticket.os_number);
             const safeDevice = this.escapeHtml(ticket.device_model);

             // Custom context without duplication
             const cleanContext = {
                 client: `<b>${safeClientName} da OS ${safeOsNumber}</b>`,
                 device: `<b>${safeDevice}</b>`
             };

             const companyName = this.getOutsourcedCompany(ticket.outsourced_company_id);

             await this.updateStatus(ticket, 'Teste Final', {
                 test_start_at: null // Reset test status to ensure "Start Test" appears
             }, {
                 action: 'Recebeu de Terceiro',
                 details: `${cleanContext.device} de ${cleanContext.client} recebido da ${companyName}. Enviado para testes.`
             });
        },

        cobrarOutsourced(ticket) {
            const phone = this.getOutsourcedPhone(ticket.outsourced_company_id);
            if (!phone) return this.notify("Telefone não cadastrado.", "error");

            // Context requested by user
            const msg = `Olá, gostaria de saber sobre o andamento do aparelho ${ticket.device_model} (OS ${ticket.os_number}) enviado para vocês.`;

            let number = phone.replace(/\D/g, '');
            // Ensure 55 prefix if not present (assuming BR number logic generally)
            if (!number.startsWith('55') && number.length >= 10) {
                number = '55' + number;
            }

            window.open(`https://wa.me/${number}?text=${encodeURIComponent(msg)}`, '_blank');
        },

        // --- LOGISTICS FUNCTIONS ---
        openLogisticsModal(ticket) {
            this.selectedTicket = ticket;
            this.logisticsMode = 'initial';
            this.logisticsForm = { carrier: '', tracking: '' };
            this.modals.logistics = true;
        },

        async confirmLogisticsOption(type) {
            if (type === 'pickup') {
                // Execute standard "Disponibilizar" logic for Client Pickup
                this.loading = true;
                try {
                    const ticket = this.selectedTicket;
                    const ctx = this.getLogContext(ticket);

                    await this.logTicketAction(ticket.id, 'Disponibilizou Retirada', `O ${ctx.device} de ${ctx.client} foi disponibilizado.`);

                    await this.supabaseFetch(`tickets?id=eq.${ticket.id}`, 'PATCH', {
                        pickup_available: true,
                        pickup_available_at: new Date().toISOString(),
                        delivery_method: 'pickup'
                    });

                    this.notify("Disponibilizado para retirada.");
                    this.modals.logistics = false;
                    this.modals.viewTicket = false;
                    await this.fetchTickets();

                    // Open WhatsApp automatically as per standard flow
                    this.sendTrackingWhatsApp();
                } catch(e) {
                    this.notify("Erro: " + e.message, "error");
                } finally {
                    this.loading = false;
                }
            }
        },

        async confirmCarrier() {
            const form = this.logisticsForm;
            // Validation: If tracking exists, carrier is mandatory.
            if (form.tracking && !form.carrier) {
                return this.notify("Transportadora é obrigatória se houver código de rastreio.", "error");
            }
            if (this.logisticsMode === 'carrier_form' && !form.carrier) {
                 return this.notify("Informe a transportadora.", "error");
            }

            this.loading = true;
            try {
                const ticket = this.selectedTicket;
                const ctx = this.getLogContext(ticket);
                const updates = {};
                let logMsg = '';

                if (this.logisticsMode === 'add_tracking') {
                    // Updating existing carrier delivery
                    updates.tracking_code = form.tracking;
                    // User requested specific text for this action:
                    logMsg = `Código de rastreio do cliente foi adicionado e o numero do rastrio ${form.tracking}`;
                    await this.logTicketAction(ticket.id, 'Adicionou Rastreio', logMsg);
                } else {
                    // Initial Carrier Setup
                    updates.delivery_method = 'carrier';
                    updates.carrier_name = form.carrier;
                    updates.tracking_code = form.tracking || null;
                    updates.pickup_available = true; // Mark as "moved forward" conceptually
                    updates.pickup_available_at = new Date().toISOString();

                    logMsg = `Aparelho ${ctx.device} de ${ctx.client} foi enviado por transportadora.`;
                    if (form.tracking) {
                        logMsg += ` Código de Rastreio ${form.tracking}.`;
                    }
                    await this.logTicketAction(ticket.id, 'Enviou Transportadora', logMsg);

                    // Send specific WhatsApp for Carrier
                    this.sendCarrierWhatsApp(ticket, form.carrier, form.tracking);
                }

                await this.supabaseFetch(`tickets?id=eq.${ticket.id}`, 'PATCH', updates);

                this.notify("Informações de envio atualizadas!");
                this.modals.logistics = false;
                this.modals.viewTicket = false;
                await this.fetchTickets();
            } catch(e) {
                this.notify("Erro ao salvar envio: " + e.message, "error");
            } finally {
                this.loading = false;
            }
        },

        addTrackingCode(ticket) {
            this.selectedTicket = ticket;
            this.logisticsMode = 'add_tracking';
            this.logisticsForm = { carrier: ticket.carrier_name || '', tracking: '' };
            this.modals.logistics = true;
        },

        async markDelivered(ticket) {
            // Equivalent to "Chegou" or "Retirado (Finalizar)"
            const ctx = this.getLogContext(ticket);
            let action = 'Finalizou Entrega';
            let details = `${ctx.device} de ${ctx.client} foi retirado.`;

            if (ticket.delivery_method === 'carrier') {
                action = 'Entrega Confirmada';
                // Specific text requested: "[Model] do [Client] da OS [Number] chegou ao seu destino."
                details = `${ctx.device} do ${ctx.client} chegou ao seu destino.`;
            }

            await this.updateStatus(ticket, 'Finalizado', {
                delivered_at: new Date().toISOString()
            }, { action, details });
        },

        async markAvailable(ticket = this.selectedTicket) {
             if (this.trackerConfig.enable_logistics) {
                 this.openLogisticsModal(ticket);
                 return;
             }

             // Legacy Flow
             this.loading = true;
             try {
                 const ctx = this.getLogContext(ticket);
                 await this.logTicketAction(ticket.id, 'Disponibilizou Retirada', `O ${ctx.device} de ${ctx.client} foi disponibilizado.`);

                 await this.supabaseFetch(`tickets?id=eq.${ticket.id}`, 'PATCH', {
                    pickup_available: true,
                    pickup_available_at: new Date().toISOString()
                });
                await this.fetchTickets();

                // Open WhatsApp
                this.sendTrackingWhatsApp();
             } catch(e) {
                 this.notify("Erro: " + e.message, "error");
             } finally {
                this.loading = false;
             }
        },
        async confirmPickup(ticket = this.selectedTicket) {
            const ctx = this.getLogContext(ticket);
            await this.updateStatus(ticket, 'Finalizado', {
                delivered_at: new Date().toISOString()
            }, { action: 'Finalizou Entrega', details: `${ctx.client} retirou o ${ctx.device}.` });
        },

        async requestPriority(ticket) {
            this.loading = true;
            try {
                const ctx = this.getLogContext(ticket);
                await this.logTicketAction(ticket.id, 'Solicitou Prioridade', `Foi solicitado prioridade no ${ctx.device} de ${ctx.client}.`);

                await this.supabaseFetch(`tickets?id=eq.${ticket.id}`, 'PATCH', {
                    priority_requested: true
                });

                this.notify("Prioridade solicitada com sucesso!");
                await this.fetchTickets();
            } catch(e) {
                this.notify("Erro: " + e.message, "error");
            } finally {
                this.loading = false;
            }
        },

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
            if (!this.user?.workspace_id) return;
            try {
                const data = await this.supabaseFetch('rpc/get_operational_alerts', 'POST', {
                    p_workspace_id: this.user.workspace_id
                });
                if (data) {
                    this.ops = data;
                }
            } catch (e) {
                console.error("Fetch Alerts Error:", e);
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
            if (!this.user?.workspace_id) return this.notify('Erro workspace', 'error');
            if (!this.employeeForm.name || !this.employeeForm.username || !this.employeeForm.password) return this.notify('Preencha campos', 'error');
            this.loading = true;
            try {
                await this.supabaseFetch('rpc/create_employee', 'POST', {
                    p_workspace_id: this.user.workspace_id,
                    p_name: this.employeeForm.name,
                    p_username: this.employeeForm.username,
                    p_password: this.employeeForm.password,
                    p_roles: this.employeeForm.roles
                });

                this.notify('Criado!');
                this.modals.newEmployee = false;
                await this.fetchEmployees();
            } catch(e) {
                console.error(e);
                this.notify('Erro: ' + e.message, 'error');
            } finally {
                this.loading = false;
            }
        },

        openEditEmployee(emp) {
            this.employeeForm = {
                id: emp.id,
                name: emp.name,
                username: emp.username,
                password: emp.plain_password || '',
                roles: emp.roles || []
            };
            this.modals.editEmployee = true;
        },

        async updateEmployee() {
            if (!this.employeeForm.id) return;
            if (!this.employeeForm.name || !this.employeeForm.username) return this.notify('Preencha campos obrigatórios', 'error');

            this.loading = true;
            try {
                await this.supabaseFetch('rpc/update_employee', 'POST', {
                    p_id: this.employeeForm.id,
                    p_name: this.employeeForm.name,
                    p_username: this.employeeForm.username,
                    p_password: this.employeeForm.password,
                    p_roles: this.employeeForm.roles
                });

                this.notify('Atualizado!');
                this.modals.editEmployee = false;
                await this.fetchEmployees();
            } catch(e) {
                console.error(e);
                this.notify('Erro: ' + e.message, 'error');
            } finally {
                this.loading = false;
            }
        },

        async deleteEmployee(id) {
            if (!confirm('Tem certeza que deseja mover este funcionário para a Lixeira?')) return;
            try {
                await this.supabaseFetch(`employees?id=eq.${id}`, 'PATCH', {
                    deleted_at: new Date().toISOString()
                });
                this.notify('Funcionário movido para a Lixeira.');
                await this.fetchEmployees();
            } catch(e) {
                this.notify('Erro ao excluir: ' + e.message, 'error');
            }
        },

        async deleteTicket() {
            if (!this.selectedTicket) return;
            if (!confirm('Tem certeza que deseja excluir este chamado? Ele irá para a Lixeira e não aparecerá nas listagens.')) return;

            this.loading = true;
            try {
                await this.supabaseFetch(`tickets?id=eq.${this.selectedTicket.id}`, 'PATCH', {
                    deleted_at: new Date().toISOString()
                });
                this.notify('Chamado movido para a Lixeira.');
                this.modals.viewTicket = false;
                await this.fetchTickets();
            } catch(e) {
                this.notify('Erro ao excluir: ' + e.message, 'error');
            } finally {
                this.loading = false;
            }
        },

        async fetchDeletedItems() {
            if (!this.user?.workspace_id || !this.hasRole('admin')) return;
            this.loading = true;
            try {
                const tickets = await this.supabaseFetch(
                    `tickets?select=*&workspace_id=eq.${this.user.workspace_id}&deleted_at=not.is.null&order=deleted_at.desc`
                );
                this.deletedTickets = tickets || [];

                const emps = await this.supabaseFetch(
                    `employees?select=*&workspace_id=eq.${this.user.workspace_id}&deleted_at=not.is.null&order=deleted_at.desc`
                );
                this.deletedEmployees = emps || [];

            } catch(e) {
                this.notify("Erro ao buscar lixeira: " + e.message, "error");
            } finally {
                this.loading = false;
            }
        },

        async restoreItem(type, id) {
            if (!confirm("Deseja restaurar este item?")) return;
            this.loading = true;
            try {
                const endpoint = type === 'ticket' ? 'tickets' : 'employees';
                await this.supabaseFetch(`${endpoint}?id=eq.${id}`, 'PATCH', {
                    deleted_at: null
                });
                this.notify("Item restaurado!");

                await this.fetchDeletedItems();
                if (type === 'ticket') await this.fetchTickets();
                if (type === 'employee') await this.fetchEmployees();

            } catch(e) {
                this.notify("Erro ao restaurar: " + e.message, "error");
            } finally {
                this.loading = false;
            }
        },

        openRecycleBin() {
            this.fetchDeletedItems();
            this.modals.recycleBin = true;
        },

        formatDuration(ms) {
            if (!ms || Number.isNaN(ms)) return '-';
            const totalMinutes = Math.round(ms / 60000);
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
