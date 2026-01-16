
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
            enable_outsourced: false, // NEW
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
                'Aberto', 'Analise Tecnica', 'Aprovacao', 'Compra Peca',
                'Andamento Reparo', 'Teste Final', 'Retirada Cliente', 'Finalizado'
            ]
        },
        previewStatus: 'Andamento Reparo', // For Admin Preview

        // Data
        employees: [],
        tickets: [],
        techTickets: [],
        suppliers: [], // NEW
        deletedTickets: [],
        deletedEmployees: [],
        deviceModels: [],
        defectOptions: [],
        checklistTemplates: [],
        checklistTemplatesEntry: [],
        checklistTemplatesFinal: [],
        notifications: [],

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
             outsourcedStats: {} // NEW
        },

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
            is_outsourced: false, outsourced_company_id: '', outsourced_deadline: '',
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
        testFailureData: { newDeadline: '', newPriority: 'Normal', reason: '' },

        // Outsourced Form (NEW)
        outsourcedForm: {
            supplierId: '',
            deadline: '',
            newSupplierName: '',
            newSupplierPhone: ''
        },

        // Supplier Management Form
        supplierForm: { id: null, name: '', phone: '' },

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
        selectedTechFilter: 'all',

        // Kanban State
        kanbanScrollWidth: 0,

        // Search
        searchQuery: '',
        activeQuickFilter: null,
        showFinalized: true,

        // Time
        currentTime: new Date(),

        // Modals
        modals: { newEmployee: false, editEmployee: false, ticket: false, viewTicket: false, outcome: false, logs: false, calendar: false, notifications: false, recycleBin: false, logistics: false, outsourced: false, supplier: false },

        // Logistics State
        logisticsMode: 'initial', // 'initial', 'carrier_form', 'add_tracking'
        logisticsForm: { carrier: '', tracking: '' },

        // Notifications
        notificationsList: [],
        showReadNotifications: false,

        // Constants
        PRIORITIES: ['Baixa', 'Normal', 'Alta', 'Urgente'],
        // Initial columns, updated via watcher
        STATUS_COLUMNS: [
            'Aberto', 'Analise Tecnica', 'Aprovacao', 'Compra Peca',
            'Andamento Reparo', 'Teste Final', 'Retirada Cliente', 'Finalizado'
        ],
        STATUS_LABELS: {
            'Aberto': 'Aberto',
            'Analise Tecnica': 'Análise Técnica',
            'Terceirizado': 'Terceirizado', // NEW
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
                    await this.fetchSuppliers(); // NEW
                    this.fetchGlobalLogs();
                    this.setupRealtime();
                }
            } catch (err) {
                console.error("Init Error:", err);
            } finally {
                this.loading = false;
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
                if (value !== 'kanban') {
                    this.clearFilters();
                } else {
                    setTimeout(() => this.initKanbanScroll(), 100);
                }
                if (value === 'dashboard') {
                    this.fetchGlobalLogs();
                }
            });

            this.$watch('adminDashboardFilters', () => {
                this.calculateMetrics();
                if (this.adminDashboardFilters.viewType === 'chart') {
                    setTimeout(() => this.renderCharts(), 50);
                }
            });

            // Watch for Config Changes to update Columns
            this.$watch('trackerConfig.enable_outsourced', (val) => {
                this.updateStatusColumns();
            });
        },

        updateStatusColumns() {
            const base = [
                'Aberto', 'Analise Tecnica', 'Aprovacao', 'Compra Peca',
                'Andamento Reparo', 'Teste Final', 'Retirada Cliente', 'Finalizado'
            ];
            if (this.trackerConfig.enable_outsourced) {
                // Insert 'Terceirizado' after 'Aberto'
                base.splice(1, 0, 'Terceirizado');
            }
            this.STATUS_COLUMNS = base;
        },

        calculateMetrics() {
            this.ops = this.getDashboardOps();
            this.metrics = this.getAdminMetrics();
        },

        toggleAdminView() {
            this.adminDashboardFilters.viewType = this.adminDashboardFilters.viewType === 'data' ? 'chart' : 'data';
            this.calculateMetrics();
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

            const existing = supabaseClient.getChannels().find(c => c.topic === 'tickets_channel');
            if (existing && existing.state === 'joined') return;
            if (existing) supabaseClient.removeChannel(existing);

            supabaseClient
                .channel('tickets_channel')
                .on('postgres_changes', { event: '*', schema: 'public', table: 'tickets' },
                payload => {
                   this.fetchTickets();
                   if (this.selectedTicket && payload.new && payload.new.id === this.selectedTicket.id) {
                       this.selectedTicket = { ...this.selectedTicket, ...payload.new };
                   }
                })
                .subscribe();

            supabaseClient
                .channel('notifications_channel')
                .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'notifications' },
                payload => {
                    this.fetchNotifications();
                })
                .subscribe();

            supabaseClient
                .channel('ticket_logs_channel')
                .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'ticket_logs' },
                () => {
                    this.fetchGlobalLogs();
                })
                .subscribe();
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
                        this.updateStatusColumns(); // Apply config
                    }

                    localStorage.setItem('techassist_employee', JSON.stringify(emp));
                    this.notify('Bem-vindo, ' + emp.name, 'success');
                    await this.fetchEmployees();
                    this.initTechFilter();
                    await this.fetchTickets();
                    await this.fetchTemplates();
                    await this.fetchDeviceModels();
                    await this.fetchDefectOptions();
                    await this.fetchSuppliers(); // NEW
                    this.fetchGlobalLogs();

                    if (this.hasRole('tecnico') && !this.hasRole('admin') && !this.hasRole('atendente')) {
                        this.view = 'tech_orders';
                    }

                    this.setupRealtime();
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
                        this.updateStatusColumns(); // Apply config
                    }

                    await this.fetchEmployees();
                    this.initTechFilter();
                    await this.fetchTickets();
                    await this.fetchTemplates();
                    await this.fetchDeviceModels();
                    await this.fetchDefectOptions();
                    await this.fetchSuppliers(); // NEW
                    this.fetchGlobalLogs();
                    this.setupRealtime();
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

        // --- SUPPLIERS (NEW) ---
        async fetchSuppliers() {
            if (!this.user?.workspace_id) return;
            try {
                const data = await this.supabaseFetch(`suppliers?select=*&workspace_id=eq.${this.user.workspace_id}&deleted_at=is.null&order=name.asc`);
                if (data) this.suppliers = data;
            } catch (e) {
                console.error("Fetch Suppliers Error:", e);
            }
        },

        async createSupplier(name, phone) {
            if (!name) return null;
            if (!this.user?.workspace_id) return null;

            try {
                const data = await this.supabaseFetch('suppliers', 'POST', {
                    workspace_id: this.user.workspace_id,
                    name: name,
                    phone: phone
                });
                await this.fetchSuppliers();
                return data ? data[0] : null;
            } catch (e) {
                this.notify("Erro ao criar fornecedor: " + e.message, "error");
                return null;
            }
        },

        async deleteSupplier(id) {
            if (!confirm("Remover este fornecedor da lista?")) return;
            try {
                await this.supabaseFetch(`suppliers?id=eq.${id}`, 'PATCH', { deleted_at: new Date().toISOString() });
                await this.fetchSuppliers();
                this.notify("Fornecedor removido.");
            } catch (e) {
                this.notify("Erro: " + e.message, "error");
            }
        },

        openSupplierModal(supplier = null) {
            if (supplier) {
                this.supplierForm = { id: supplier.id, name: supplier.name, phone: supplier.phone || '' };
            } else {
                this.supplierForm = { id: null, name: '', phone: '' };
            }
            this.modals.supplier = true;
        },

        async saveSupplier() {
            if (!this.supplierForm.name) return this.notify("Nome é obrigatório", "error");
            this.loading = true;
            try {
                if (this.supplierForm.id) {
                    await this.supabaseFetch(`suppliers?id=eq.${this.supplierForm.id}`, 'PATCH', {
                        name: this.supplierForm.name,
                        phone: this.supplierForm.phone
                    });
                    this.notify("Fornecedor atualizado!");
                } else {
                    await this.createSupplier(this.supplierForm.name, this.supplierForm.phone);
                }
                this.modals.supplier = false;
                await this.fetchSuppliers();
            } catch (e) {
                this.notify("Erro: " + e.message, "error");
            } finally {
                this.loading = false;
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
                await this.supabaseFetch(`workspaces?id=eq.${this.user.workspace_id}`, 'PATCH', {
                    tracker_config: this.trackerConfig
                });
                if (this.view === 'management_settings') {
                    this.notify("Configurações de Gerenciamento salvas!");
                } else {
                    this.notify("Configurações de Acompanhamento salvas!");
                }
                this.updateStatusColumns();
            } catch (e) {
                this.notify("Erro ao salvar: " + e.message, "error");
            } finally {
                this.loading = false;
            }
        },

        // ... (Logo upload logic unchanged) ...
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
                    enable_outsourced: false,
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
                        'Aberto', 'Analise Tecnica', 'Aprovacao', 'Compra Peca',
                        'Andamento Reparo', 'Teste Final', 'Retirada Cliente', 'Finalizado'
                    ]
                };
                this.updateStatusColumns();
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

        // ... (fetchTickets, fetchTemplates, etc. unchanged) ...
        async fetchTickets(retryCount = 0) {
            if (!this.user?.workspace_id) return;

            try {
                // Ensure we get joined tables if needed, but select * works for now
                // For suppliers, we need to fetch separately or join.
                // Assuming supplier details are fetched via separate fetchSuppliers or I need to join here.
                // Actually, ticket has outsourced_company_id. We can find name from this.suppliers.
                const data = await this.supabaseFetch(
                    `tickets?select=*&workspace_id=eq.${this.user.workspace_id}&deleted_at=is.null&order=created_at.desc`
                );

                if (data) {
                    this.tickets = data;

                    let filteredTechTickets = data;
                    let effectiveFilter = this.selectedTechFilter;

                    const isTechOnly = !this.hasRole('admin') && this.hasRole('tecnico');

                    if (isTechOnly && this.user) {
                        effectiveFilter = this.user.id;
                        this.selectedTechFilter = this.user.id;
                    }

                    if (effectiveFilter && effectiveFilter !== 'all') {
                        filteredTechTickets = filteredTechTickets.filter(t => t.technician_id == effectiveFilter || t.technician_id == null);
                    } else if (isTechOnly) {
                         console.warn("Tech View Security: Filter missing, hiding all tickets.");
                         filteredTechTickets = [];
                    }

                    this.techTickets = filteredTechTickets.filter(t =>
                        ['Analise Tecnica', 'Andamento Reparo'].includes(t.status)
                    ).sort((a, b) => {
                        if (a.priority_requested && !b.priority_requested) return -1;
                        if (!a.priority_requested && b.priority_requested) return 1;

                        const pOrder = { 'Urgente': 0, 'Alta': 1, 'Normal': 2, 'Baixa': 3 };
                        const pDiff = pOrder[a.priority] - pOrder[b.priority];
                        if (pDiff !== 0) return pDiff;

                        return new Date(a.deadline || 0) - new Date(b.deadline || 0);
                    });

                    this.calculateMetrics();
                }
            } catch (err) {
                 console.warn("Fetch exception:", err);
                 if (retryCount < 2) {
                     setTimeout(() => this.fetchTickets(retryCount + 1), 1000);
                 } else {
                     console.error("Final ticket fetch failure");
                 }
            }
        },

        // ... (Other fetch/create functions unchanged) ...
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

        // ... (createDeviceModel, createDefectOption, deleteDeviceModel, deleteDefectOption, openNewTicketModal, addChecklistItem, etc. unchanged) ...

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
                is_outsourced: false, outsourced_company_id: '', outsourced_deadline: '',
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

             if (!this.ticketForm.is_outsourced && !this.ticketForm.technician_id) {
                 return this.notify("Selecione um Técnico Responsável ou 'Todos'.", "error");
             }

             if (this.ticketForm.is_outsourced && !this.ticketForm.outsourced_company_id) {
                 return this.notify("Selecione um Parceiro/Fornecedor.", "error");
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
                 if (techId === 'all' || techId === '') techId = null;

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
                     technician_id: techId,
                     checklist_data: this.ticketForm.checklist,
                     checklist_final_data: this.ticketForm.checklist_final,
                     photos_urls: this.ticketForm.photos,
                     status: 'Aberto',
                     created_by_name: this.user.name,
                     // Outsourced Fields
                     is_outsourced: this.ticketForm.is_outsourced,
                     outsourced_company_id: (this.ticketForm.is_outsourced && this.ticketForm.outsourced_company_id) ? this.ticketForm.outsourced_company_id : null
                     // Deadline NOT set at creation
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

        // --- RESTORED FUNCTIONS ---

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
                    photos_urls: this.selectedTicket.photos_urls // In case photos were removed/added
                });
                this.notify("Anotações salvas.");
                // Note: we don't necessarily need to fetchTickets if we just updated local selectedTicket
            } catch (e) {
                this.notify("Erro ao salvar: " + e.message, "error");
            } finally {
                this.loading = false;
            }
        },

        async uploadTicketPhoto(file, ticketId) {
            const path = `${this.user.workspace_id}/${ticketId}/${Date.now()}_${file.name}`;
            const url = `${SUPABASE_URL}/storage/v1/object/ticket_photos/${path}`;

            let token = this.session?.access_token || SUPABASE_KEY;
            const headers = {
                'apikey': SUPABASE_KEY,
                'Authorization': `Bearer ${token}`,
                'x-workspace-id': this.user.workspace_id,
                'Content-Type': file.type
            };

            const response = await fetch(url, { method: 'POST', headers, body: file });
            if (!response.ok) throw new Error("Upload failed");

            return `${SUPABASE_URL}/storage/v1/object/public/ticket_photos/${path}`;
        },

        async handlePhotoUpload(event, type) {
            const files = event.target.files;
            if (!files.length) return;

            this.loading = true;
            try {
                for (let i = 0; i < files.length; i++) {
                    const file = files[i];
                    // If 'new', we upload to a temp folder or just wait? No, upload immediately to storage is better
                    // But we don't have ticket ID for new ticket.
                    // For existing ticket ('existing'), use ticket ID.
                    let ticketId = (type === 'existing' && this.selectedTicket) ? this.selectedTicket.id : 'temp';

                    const publicUrl = await this.uploadTicketPhoto(file, ticketId);

                    if (type === 'existing' && this.selectedTicket) {
                        this.selectedTicket.photos_urls.push(publicUrl);
                        // Save immediately
                        await this.supabaseFetch(`tickets?id=eq.${this.selectedTicket.id}`, 'PATCH', {
                            photos_urls: this.selectedTicket.photos_urls
                        });
                    } else if (type === 'new') {
                        this.ticketForm.photos.push(publicUrl);
                    }
                }
                this.notify("Fotos enviadas!");
            } catch (e) {
                this.notify("Erro upload: " + e.message, "error");
            } finally {
                this.loading = false;
            }
        },

        removePhoto(index, type) {
            if (type === 'existing' && this.selectedTicket) {
                this.selectedTicket.photos_urls.splice(index, 1);
                // Save
                this.saveTicketChanges(); // Reuse save
            } else if (type === 'new') {
                this.ticketForm.photos.splice(index, 1);
            }
        },

        getTrackingLink(ticketId) {
            // Assuming current URL is the base
            const baseUrl = window.location.origin + window.location.pathname.replace('index.html', '');
            return `${baseUrl}acompanhar.html?id=${ticketId}`;
        },

        openShareModal() {
            if (!this.selectedTicket) return;
            this.showShareModal = true;
        },

        async copyTrackingLink() {
            if (!this.selectedTicket) return;
            const link = this.getTrackingLink(this.selectedTicket.id);
            try {
                await navigator.clipboard.writeText(link);
                this.notify("Link copiado!");
            } catch (e) {
                this.notify("Erro ao copiar.", "error");
            }
        },

        sendTrackingWhatsApp() {
            if (!this.selectedTicket) return;
            const ticket = this.selectedTicket;
            if (!ticket.contact_info) return this.notify("Cliente sem contato.", "error");

            const link = this.getTrackingLink(ticket.id);
            const clientName = ticket.client_name.split(' ')[0];
            const msg = `Olá ${clientName}, acompanhe o status do seu ${ticket.device_model} (OS ${ticket.os_number}) pelo link: ${link}`;

            this.openWhatsApp(ticket.contact_info);
            // Wait a moment for new tab, then try opening with text (can't do both easily without user interaction in some browsers)
            let number = ticket.contact_info.replace(/\D/g, '');
            if (number.length <= 11) number = '55' + number;
            window.open(`https://wa.me/${number}?text=${encodeURIComponent(msg)}`, '_blank');
        },

        sendCarrierWhatsApp(ticket, carrier, code) {
            if (!ticket.contact_info) return;
            const clientName = ticket.client_name.split(' ')[0];
            let msg = `Olá ${clientName}, seu aparelho ${ticket.device_model} (OS ${ticket.os_number}) foi enviado via ${carrier}.`;
            if (code) msg += ` Código de rastreio: ${code}`;

            let number = ticket.contact_info.replace(/\D/g, '');
            if (number.length <= 11) number = '55' + number;
            window.open(`https://wa.me/${number}?text=${encodeURIComponent(msg)}`, '_blank');
        },

        // --- INTERNAL NOTES ---
        async fetchInternalNotes(ticketId) {
            try {
                const data = await this.supabaseFetch(`internal_notes?ticket_id=eq.${ticketId}&order=created_at.desc`);
                if (data) this.internalNotes = data;
            } catch(e) {
                console.error(e);
            }
        },

        async fetchGeneralNotes() {
            if (!this.user?.workspace_id) return;
            try {
                let query = `internal_notes?workspace_id=eq.${this.user.workspace_id}&ticket_id=is.null&order=created_at.desc`;
                if (!this.showResolvedNotes) {
                    query += `&is_resolved=eq.false`;
                }
                // Date filter
                if (this.noteDateFilter) {
                    // Simple contains or range? Let's do >= start of day
                    // Supabase filtering on date string might need specific format.
                    // Let's rely on client side filter for simplicity or improved query if needed.
                    // Actually, let's filter client side for date to avoid complex query construction here
                }

                const data = await this.supabaseFetch(query);
                if (data) {
                    this.generalNotes = data.filter(n => {
                        if (this.noteDateFilter) {
                            return n.created_at.startsWith(this.noteDateFilter);
                        }
                        return true;
                    });
                }
            } catch(e) { console.error(e); }
        },

        handleNoteInput(event, target) {
            this.mentionTarget = target;
            const text = event.target.value;
            const cursor = event.target.selectionStart;
            this.mentionCursorPos = cursor;

            // Check for @
            const lastAt = text.lastIndexOf('@', cursor - 1);
            if (lastAt !== -1) {
                const query = text.substring(lastAt + 1, cursor);
                if (!query.includes(' ')) {
                    this.mentionQuery = query;
                    this.showMentionList = true;
                    this.mentionList = this.employees.filter(e =>
                        e.name.toLowerCase().includes(query.toLowerCase()) ||
                        e.username.toLowerCase().includes(query.toLowerCase())
                    );
                    return;
                }
            }
            this.showMentionList = false;
        },

        selectMention(emp) {
            const targetProp = this.mentionTarget === 'internal' ? 'newNoteText' : 'newGeneralNoteText';
            const text = this[targetProp];
            const lastAt = text.lastIndexOf('@', this.mentionCursorPos - 1);

            const newText = text.substring(0, lastAt) + `@${emp.username} ` + text.substring(this.mentionCursorPos);
            this[targetProp] = newText;
            this.showMentionList = false;
            // focus back? tricky with alpine
        },

        formatNoteContent(content) {
            if (!content) return '';
            // Highlight mentions
            return this.escapeHtml(content).replace(/@(\w+)/g, '<span class="text-brand-500 font-bold">@$1</span>');
        },

        async sendNote(ticketId = null, isGeneral = false) {
            const text = isGeneral ? this.newGeneralNoteText : this.newNoteText;
            const isChecklist = isGeneral ? this.generalNoteIsChecklist : this.noteIsChecklist;
            const checklistItems = isGeneral ? this.generalNoteChecklistItems : this.noteChecklistItems;

            if ((!text || !text.trim()) && (!isChecklist || checklistItems.length === 0)) return;

            this.loading = true;
            try {
                const noteData = {
                    workspace_id: this.user.workspace_id,
                    ticket_id: ticketId, // Null for general
                    author_id: this.user.id,
                    author_name: this.user.name,
                    content: text,
                    checklist_data: isChecklist ? checklistItems : null
                };

                await this.supabaseFetch('internal_notes', 'POST', noteData);

                if (isGeneral) {
                    this.newGeneralNoteText = '';
                    this.generalNoteChecklistItems = [];
                    this.generalNoteIsChecklist = false;
                    await this.fetchGeneralNotes();
                } else {
                    this.newNoteText = '';
                    this.noteChecklistItems = [];
                    this.noteIsChecklist = false;
                    await this.fetchInternalNotes(ticketId);
                }
            } catch(e) {
                this.notify("Erro ao enviar nota: " + e.message, "error");
            } finally {
                this.loading = false;
            }
        },

        addNoteChecklistItem(isGeneral = false) {
            const target = isGeneral ? this.generalNoteChecklistItems : this.noteChecklistItems;
            target.push({ item: '', ok: false }); // Empty item to be filled
        },

        removeNoteChecklistItem(index, isGeneral = false) {
            const target = isGeneral ? this.generalNoteChecklistItems : this.noteChecklistItems;
            target.splice(index, 1);
        },

        async toggleNoteCheckStatus(note, index) {
            // Update local state is handled by x-model, just save
            // But note is in loop.
            // note.checklist_data[index].ok is flipped.
            try {
                await this.supabaseFetch(`internal_notes?id=eq.${note.id}`, 'PATCH', {
                    checklist_data: note.checklist_data
                });
            } catch(e) { console.error(e); }
        },

        async resolveNote(note) {
            try {
                await this.supabaseFetch(`internal_notes?id=eq.${note.id}`, 'PATCH', {
                    is_resolved: !note.is_resolved
                });
                if (!note.ticket_id) this.fetchGeneralNotes();
                else this.fetchInternalNotes(note.ticket_id);
            } catch(e) { console.error(e); }
        },

        async archiveNote(note) {
            if (!confirm("Arquivar esta nota?")) return;
            try {
                await this.supabaseFetch(`internal_notes?id=eq.${note.id}`, 'DELETE');
                if (!note.ticket_id) this.fetchGeneralNotes();
                else this.fetchInternalNotes(note.ticket_id);
            } catch(e) { console.error(e); }
        },

        async startBudget(ticket) {
            this.selectedTicket = ticket;
            // Does not move status, just opens modal? Or moves to Analise?
            // Actually usually 'Aberto' -> 'Analise' is startAnalysis.
            // 'Aguardando Aprovação' -> 'Orçamento' button just opens details to send budget?
            // "The 'Start Budget' action... is explicitly excluded from generating an Activity Log".
            // It seems it just opens the ticket details view.
            this.viewTicketDetails(ticket);
        },

        async sendBudget() {
            if (!this.selectedTicket) return;
            const ticket = this.selectedTicket;
            this.loading = true;
            try {
                const ctx = this.getLogContext(ticket);
                await this.updateStatus(ticket, 'Aprovacao', {
                    budget_status: 'Enviado',
                    budget_sent_at: new Date().toISOString()
                }, { action: 'Enviou Orçamento', details: `Orçamento enviado para ${ctx.client}. Aguardando aprovação.` });

                // Open WhatsApp with Budget Message?
                // Optional, but good UX.
            } catch(e) {
                this.notify("Erro: " + e.message, "error");
            } finally {
                this.loading = false;
            }
        },

        async approveRepair() {
            if (!this.selectedTicket) return;
            const ctx = this.getLogContext(this.selectedTicket);
            // Move to Compra Peca OR Andamento Reparo based on parts?
            // Simplification: Go to 'Compra Peca' first if parts needed?
            // Or usually straight to 'Andamento Reparo' if parts in stock?
            // Let's assume standard flow: Approved -> Compra Peca (check stock) -> Reparo.

            await this.updateStatus(this.selectedTicket, 'Compra Peca', {
                approved_at: new Date().toISOString()
            }, { action: 'Aprovou Orçamento', details: `Orçamento aprovado pelo cliente.` });
        },

        async denyRepair() {
            if (!this.selectedTicket) return;
            // Denied -> Retirada (without repair)
            const ctx = this.getLogContext(this.selectedTicket);
            await this.updateStatus(this.selectedTicket, 'Retirada Cliente', {
                approved_at: null, // Denied
                repair_successful: false // Technically didn't succeed
            }, { action: 'Reprovou Orçamento', details: `Orçamento reprovado pelo cliente. Disponível para retirada.` });
        },

        async markPurchased() {
            if (!this.selectedTicket) return;
            await this.updateStatus(this.selectedTicket, 'Compra Peca', {
                parts_status: 'Comprado'
            }, { action: 'Comprou Peças', details: `Peças solicitadas foram compradas.` });
        },

        async confirmReceived() {
            if (!this.selectedTicket) return;
            // Parts received -> Start Repair
            const ctx = this.getLogContext(this.selectedTicket);
            await this.updateStatus(this.selectedTicket, 'Andamento Reparo', {
                parts_status: 'Recebido'
            }, { action: 'Recebeu Peças', details: `Peças recebidas. Aparelho liberado para reparo.` });
        },

        async startRepair() {
            if (!this.selectedTicket) return;
            const ctx = this.getLogContext(this.selectedTicket);
            await this.updateStatus(this.selectedTicket, 'Andamento Reparo', {
                repair_start_at: new Date().toISOString()
            }, { action: 'Iniciou Reparo', details: `Técnico iniciou o reparo no ${ctx.device}.` });
        },

        openOutcomeModal(mode, ticket = null) {
            if (ticket) this.selectedTicket = ticket;
            this.outcomeMode = mode; // 'repair' or 'test'
            this.modals.outcome = true;
            this.showTestFailureForm = false;
            this.testFailureData = { newDeadline: '', newPriority: 'Normal', reason: '', returnToOutsourced: false };
        },

        async finishRepair(success) {
            const ticket = this.selectedTicket;
            const ctx = this.getLogContext(ticket);
            this.modals.outcome = false;

            if (success) {
                await this.updateStatus(ticket, 'Teste Final', {
                    repair_end_at: new Date().toISOString(),
                    repair_successful: true
                }, { action: 'Finalizou Reparo', details: `Reparo concluído. Enviado para testes finais.` });
            } else {
                // Failed repair? Maybe straight to delivery as failed? Or stay in repair?
                // Usually "Concluído sem sucesso" -> Finalizado/Retirada
                await this.updateStatus(ticket, 'Retirada Cliente', {
                    repair_end_at: new Date().toISOString(),
                    repair_successful: false
                }, { action: 'Falha no Reparo', details: `Reparo não foi possível. Liberado para retirada.` });
            }
        },

        async startTest(ticket) {
            const t = ticket || this.selectedTicket;
            if (!t) return;
            const ctx = this.getLogContext(t);
            await this.updateStatus(t, 'Teste Final', {
                test_start_at: new Date().toISOString()
            }, { action: 'Iniciou Testes', details: `Iniciada bateria de testes no ${ctx.device}.` });
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
    }
}
