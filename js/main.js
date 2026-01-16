
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
            // OUTSOURCED FLOW CHECK
            if (this.trackerConfig.enable_outsourced) {
                // If clicked, we just open the outsourced modal for now?
                // No, the prompt says: "O botão Iniciar analise muda so para Iniciar... quando acionar ele vai da duas opção... enviar para analise... ou terceiro".
                // I will handle this via UI (dropdown). The `startAnalysis` function will now be strictly "Enviar para Análise".
                // I will add `startOutsourcedFlow` separately.
            }

            const ctx = this.getLogContext(ticket);
            await this.updateStatus(ticket, 'Analise Tecnica', {}, {
                action: 'Iniciou Atendimento',
                details: `${ctx.device} de ${ctx.client} enviado para análise do técnico.`
            });
        },

        startOutsourcedFlow(ticket) {
            this.selectedTicket = ticket;
            // Pre-fill if already outsourced
            this.outsourcedForm = {
                supplierId: ticket.outsourced_company_id || '',
                deadline: ticket.outsourced_deadline ? this.formatDateForInput(ticket.outsourced_deadline) : '',
                newSupplierName: '',
                newSupplierPhone: ''
            };
            this.modals.outsourced = true;
        },

        formatDateForInput(dateStr) {
            if (!dateStr) return '';
            const d = new Date(dateStr);
            const pad = (n) => n < 10 ? '0' + n : n;
            return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
        },

        async sendToOutsourced(ticket = null, skipModal = false) {
            // Logic for pre-defined tickets (already outsourced at creation)
            if (skipModal && ticket && ticket.is_outsourced) {
                if (!confirm(`Confirmar envio para ${this.getSupplierName(ticket.outsourced_company_id)}?`)) return;

                this.loading = true;
                try {
                    const ctx = this.getLogContext(ticket);
                    const supplierName = this.getSupplierName(ticket.outsourced_company_id);
                    const deadlineStr = ticket.outsourced_deadline ? new Date(ticket.outsourced_deadline).toLocaleString() : 'S/ Prazo';

                    await this.updateStatus(ticket, 'Terceirizado', {
                        outsourced_at: new Date().toISOString()
                    }, {
                        action: 'Enviou Terceirizado',
                        details: `${ctx.device} de ${ctx.client} enviado para ${supplierName}. Prazo: ${deadlineStr}.`
                    });
                    this.modals.viewTicket = false; // Close detail modal if open
                } catch(e) {
                    this.notify("Erro: " + e.message, "error");
                } finally {
                    this.loading = false;
                }
                return;
            }

            // Standard Logic (via Modal)
            if (!this.selectedTicket) return;
            const form = this.outsourcedForm;
            let supplierId = form.supplierId;

            if (!supplierId) return this.notify("Selecione um fornecedor", "error");
            if (!form.deadline) return this.notify("Informe o prazo do fornecedor", "error");

            this.loading = true;
            try {
                const ctx = this.getLogContext(this.selectedTicket);
                const supplier = this.suppliers.find(s => s.id === supplierId);
                const supplierName = supplier ? supplier.name : 'Terceiro';

                await this.updateStatus(this.selectedTicket, 'Terceirizado', {
                    is_outsourced: true,
                    outsourced_company_id: supplierId,
                    outsourced_deadline: this.toUTC(form.deadline),
                    outsourced_at: new Date().toISOString()
                }, {
                    action: 'Enviou Terceirizado',
                    details: `${ctx.device} de ${ctx.client} enviado para ${supplierName}. Prazo: ${new Date(form.deadline).toLocaleString()}.`
                });

                this.modals.outsourced = false;
                this.modals.viewTicket = false;
            } catch(e) {
                this.notify("Erro: " + e.message, "error");
            } finally {
                this.loading = false;
            }
        },

        getSupplierName(id) {
            const s = this.suppliers.find(x => x.id === id);
            return s ? s.name : 'Terceiro';
        },

        async outsourcedReceived(ticket) {
            const ctx = this.getLogContext(ticket);
            // Move to 'Teste Final'
            // Format: [Modelo] do cliente [Nome] da os [Número] recebido do fornecedor. Enviado para teste.
            // getLogContext returns { client: "<b>Name da OS #123</b>", device: "<b>Iphone 13</b>" }
            // We need to construct it carefully to match request.
            // Request: "Iphone 13 do cliente João da os 123 recebido do fornecedor. Enviado para teste"

            const device = ticket.device_model;
            const client = ticket.client_name;
            const os = ticket.os_number;

            // Using bold formatting consistent with getLogContext style but specific order
            const details = `<b>${this.escapeHtml(device)}</b> do cliente <b>${this.escapeHtml(client)}</b> da OS <b>${this.escapeHtml(os)}</b> recebido do fornecedor. Enviado para teste.`;

            await this.updateStatus(ticket, 'Teste Final', {}, {
                action: 'Recebeu do Terceiro',
                details: details
            });
        },

        chargeSupplier(ticket) {
            if (!ticket.outsourced_company_id) return;
            const supplier = this.suppliers.find(s => s.id === ticket.outsourced_company_id);
            if (!supplier || !supplier.phone) return this.notify("Fornecedor sem telefone", "error");

            const ctx = this.getLogContext(ticket);
            // Remove html tags for whatsapp message
            const clientName = ticket.client_name;
            const device = ticket.device_model;
            const os = ticket.os_number;

            const msg = `Olá ${supplier.name}, gostaria de saber sobre o andamento do aparelho ${device} (OS ${os}) do cliente ${clientName}.`;
            this.openWhatsApp(supplier.phone);

            // Or better, directly open with message
            let number = supplier.phone.replace(/\D/g, '');
            if (number.length <= 11) number = '55' + number;
            window.open(`https://wa.me/${number}?text=${encodeURIComponent(msg)}`, '_blank');
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

        // ... (openWhatsApp, startBudget, sendBudget, approveRepair, denyRepair, markPurchased, confirmReceived, startRepair, openOutcomeModal, finishRepair, startTest - unchanged) ...
        openWhatsApp(phone) {
            if (!phone) return this.notify("Telefone não cadastrado.", "error");

            let number = phone.replace(/\D/g, '');

            if (number.length < 10) return this.notify("Número inválido para WhatsApp.", "error");

            if (number.length <= 11) {
                number = '55' + number;
            }

            window.open(`https://wa.me/${number}`, '_blank');
        },

        async concludeTest(success) {
            const ticket = this.selectedTicket;
            const ctx = this.getLogContext(ticket);

            if (success) {
                this.modals.outcome = false;

                // Redirect logic based on Logistics Mode
                // If outsourced, logic is same (approved -> ready for pickup)
                await this.updateStatus(ticket, 'Retirada Cliente', {}, { action: 'Concluiu Testes', details: `O ${ctx.device} de ${ctx.client} foi aprovado.` });
            } else {
                if (!this.testFailureData.newDeadline) return this.notify("Defina um novo prazo", "error");

                // If outsourced and failed
                if (ticket.is_outsourced && this.testFailureData.returnToOutsourced) {
                     // Return to Outsourced
                     await this.updateStatus(ticket, 'Terceirizado', {
                         outsourced_deadline: this.toUTC(this.testFailureData.newDeadline),
                         outsourced_return_count: (ticket.outsourced_return_count || 0) + 1,
                         test_notes: [...(ticket.test_notes || []), {
                             date: new Date().toISOString(),
                             text: 'Reprovado (Terceirizado): ' + this.testFailureData.reason,
                             user: this.user.name
                         }]
                     }, {
                         action: 'Devolveu ao Terceiro',
                         details: `Aparelho ${ctx.device} reprovado nos testes e devolvido ao fornecedor. Motivo: ${this.testFailureData.reason}`
                     });
                     this.modals.outcome = false;
                     this.notify("Devolvido ao fornecedor.");
                     return;
                }

                // Standard Failure
                if (!this.testFailureData.reason) return this.notify("Descreva o defeito apresentado", "error");

                const newNote = {
                    date: new Date().toISOString(),
                    text: this.testFailureData.reason,
                    user: this.user.name
                };

                const existingNotes = Array.isArray(ticket.test_notes) ? ticket.test_notes : [];
                const updatedNotes = [...existingNotes, newNote];

                // If it was outsourced but now "Realizar Reparo" internal
                let logDetails = 'Retornado para Reparo. Defeito: ' + this.testFailureData.reason;
                if (ticket.is_outsourced && !this.testFailureData.returnToOutsourced) {
                    logDetails += ' (Assumido internamente após falha do terceiro)';
                    // We might want to keep is_outsourced true for stats, but workflow is now internal
                }

                this.modals.outcome = false;
                await this.updateStatus(ticket, 'Andamento Reparo', {
                    deadline: this.toUTC(this.testFailureData.newDeadline),
                    priority: this.testFailureData.newPriority,
                    repair_start_at: null,
                    test_start_at: null,
                    status: 'Andamento Reparo', // Forced status
                    test_notes: updatedNotes
                }, { action: 'Reprovou Testes', details: logDetails });
                this.notify("Retornado para reparo com urgência!");
            }
        },

        // --- LOGISTICS FUNCTIONS ---
        // ... (openLogisticsModal, confirmLogisticsOption, confirmCarrier, addTrackingCode, markDelivered, markAvailable, confirmPickup, requestPriority - unchanged) ...
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

        // ... (getCalendarTickets, etc. unchanged) ...
        getKanbanTickets(status) {
            let list = this.tickets.filter(t => t.status === status && this.matchesSearch(t));

            if (status === 'Terceirizado') {
                list.sort((a, b) => {
                    // Sort by outsourced_deadline ascending (closest first)
                    // Treat null as far future
                    const dateA = a.outsourced_deadline ? new Date(a.outsourced_deadline) : new Date(8640000000000000);
                    const dateB = b.outsourced_deadline ? new Date(b.outsourced_deadline) : new Date(8640000000000000);
                    return dateA - dateB;
                });
            }

            return list;
        },

        getCalendarTickets() {
            let source = this.tickets.filter(t => t.status !== 'Finalizado' && t.deadline);

            let effectiveFilter = this.selectedTechFilter;
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

        // ... (escapeHtml, getLogContext, etc. unchanged) ...
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

            const client = `<b>${safeClientName} da OS ${safeOsNumber}</b>`;
            const device = `<b>${safeDevice}</b>`;
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
                this.selectedTechFilter = 'all';
            } else if (this.hasRole('tecnico') && this.user && this.user.id) {
                this.selectedTechFilter = this.user.id;
                console.log("Filter set to self (Tech):", this.selectedTechFilter);
            } else {
                this.selectedTechFilter = 'all';
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

        // --- PREVIEW LOGIC ---
        // ... (unchanged) ...
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

        // DASHBOARD OPERATIONAL METRICS
        getDashboardOps() {
            const now = new Date();
            const tickets = this.tickets || [];

            const pendingBudgets = tickets.filter(t => t.status === 'Aprovacao' && t.budget_status !== 'Enviado');

            const waitingBudgetResponse = tickets.filter(t => t.status === 'Aprovacao' && t.budget_status === 'Enviado');

            const pendingPickups = tickets.filter(t => t.status === 'Retirada Cliente' && !t.pickup_available);

            // Logistics specific lists
            const pendingTracking = tickets.filter(t =>
                t.status === 'Retirada Cliente' &&
                t.delivery_method === 'carrier' &&
                !t.tracking_code
            );

            const pendingDelivery = tickets.filter(t =>
                t.status === 'Retirada Cliente' &&
                (
                    (t.delivery_method === 'pickup' && t.pickup_available) ||
                    (t.delivery_method === 'carrier' && t.tracking_code)
                )
            );

            // Outsourced Pending
            const pendingOutsourced = tickets.filter(t => t.status === 'Terceirizado').sort((a,b) => {
                const dateA = a.outsourced_deadline ? new Date(a.outsourced_deadline) : new Date(8640000000000000);
                const dateB = b.outsourced_deadline ? new Date(b.outsourced_deadline) : new Date(8640000000000000);
                return dateA - dateB;
            });

            const urgentAnalysis = tickets
                .filter(t => t.status === 'Analise Tecnica' && t.analysis_deadline)
                .sort((a, b) => new Date(a.analysis_deadline) - new Date(b.analysis_deadline))
                .slice(0, 5);

            const delayedDeliveries = tickets.filter(t =>
                t.deadline &&
                new Date(t.deadline) < now &&
                !['Retirada Cliente', 'Finalizado'].includes(t.status)
            );

            const priorityTickets = tickets.filter(t => t.priority_requested && !['Retirada Cliente', 'Finalizado'].includes(t.status));

            const pendingPurchase = tickets.filter(t => t.status === 'Compra Peca' && t.parts_status !== 'Comprado');

            const pendingReceipt = tickets.filter(t => t.status === 'Compra Peca' && t.parts_status === 'Comprado');

            const pendingTech = tickets.filter(t => t.status === 'Aberto');

            return {
                pendingBudgets,
                waitingBudgetResponse,
                pendingPickups,
                urgentAnalysis,
                delayedDeliveries,
                priorityTickets,
                pendingPurchase,
                pendingReceipt,
                pendingTech,
                pendingTracking,
                pendingDelivery,
                pendingOutsourced // NEW
            };
        },

        // ... (applyQuickFilter, clearFilters, matchesSearch, getOverdueTime, getDuration, etc. unchanged) ...
        applyQuickFilter(type) {
            this.searchQuery = '';
            this.view = 'kanban';
            const now = new Date();

            this.activeQuickFilter = type;
        },

        clearFilters() {
            this.searchQuery = '';
            this.activeQuickFilter = null;
        },

        matchesSearch(ticket) {
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

        // ... (createEmployee, openEditEmployee, updateEmployee, deleteEmployee, deleteTicket, fetchDeletedItems, restoreItem, openRecycleBin, formatDuration, toArray, getAdminFilteredTickets, getAdminRangeDays, getTopItems) ...
        // ... (skipping unchanged code for brevity, but will include in write_file) ...

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

        getAdminFilteredTickets() {
            if (!this.tickets || !this.tickets.length) return [];

            const { dateStart, dateEnd, deviceModel, defect, technician, status } = this.adminDashboardFilters;
            const startDate = dateStart ? new Date(`${dateStart}T00:00:00`) : null;
            const endDate = dateEnd ? new Date(`${dateEnd}T23:59:59`) : null;

            return this.tickets.filter(ticket => {
                const createdAt = ticket.created_at ? new Date(ticket.created_at) : null;
                if ((startDate || endDate) && !createdAt) return false;
                if (startDate && createdAt < startDate) return false;
                if (endDate && createdAt > endDate) return false;

                if (deviceModel !== 'all' && ticket.device_model !== deviceModel) return false;
                if (defect !== 'all') {
                    const defects = this.toArray(ticket.defects);
                    if (!defects.includes(defect)) return false;
                }
                if (technician !== 'all' && ticket.technician_id != technician) return false;
                if (status !== 'all' && ticket.status !== status) return false;
                return true;
            });
        },

        getAdminRangeDays(filteredTickets) {
            if (!filteredTickets.length) return 1;
            const { dateStart, dateEnd } = this.adminDashboardFilters;
            if (dateStart || dateEnd) {
                const timestamps = filteredTickets.map(t => new Date(t.created_at).getTime()).filter(Boolean);
                if (!timestamps.length) return 1;
                const start = dateStart ? new Date(`${dateStart}T00:00:00`) : new Date(Math.min(...timestamps));
                const end = dateEnd ? new Date(`${dateEnd}T23:59:59`) : new Date(Math.max(...timestamps));
                const diff = Math.max(1, Math.ceil((end - start) / 86400000));
                return diff;
            }
            const timestamps = filteredTickets.map(t => new Date(t.created_at).getTime()).filter(Boolean);
            if (!timestamps.length) return 1;
            const min = Math.min(...timestamps);
            const max = Math.max(...timestamps);
            const diff = Math.max(1, Math.ceil((max - min) / 86400000));
            return diff;
        },

        getTopItems(items, limit = 4) {
            return Object.entries(items)
                .sort((a, b) => b[1].total - a[1].total)
                .slice(0, limit)
                .map(([label, stats]) => ({ label, ...stats }));
        },

        getAdminMetrics() {
            // ... (previous stats logic) ...
            const filteredTickets = this.getAdminFilteredTickets();
            const rangeDays = this.getAdminRangeDays(filteredTickets);

            // ... (stats calculations) ...
            const successTickets = filteredTickets.filter(t => t.repair_successful !== null && t.repair_successful !== undefined);
            const successCount = successTickets.filter(t => t.repair_successful).length;
            const successRate = successTickets.length ? Math.round((successCount / successTickets.length) * 100) : null;

            const repairDurations = filteredTickets
                .filter(t => t.repair_start_at && t.repair_end_at)
                .map(t => new Date(t.repair_end_at) - new Date(t.repair_start_at))
                .filter(ms => ms > 0);
            const avgRepair = repairDurations.length ? repairDurations.reduce((a, b) => a + b, 0) / repairDurations.length : null;

            const solutionDurations = filteredTickets
                .map(t => {
                    if (!t.created_at) return null;
                    const readyAt = t.pickup_available_at || t.repair_end_at;
                    if (!readyAt) return null;
                    return new Date(readyAt) - new Date(t.created_at);
                })
                .filter(ms => ms && ms > 0);
            const avgSolution = solutionDurations.length ? solutionDurations.reduce((a, b) => a + b, 0) / solutionDurations.length : null;

            const deliveryDurations = filteredTickets
                .filter(t => t.status === 'Finalizado' && t.created_at && t.delivered_at)
                .map(t => {
                    return new Date(t.delivered_at) - new Date(t.created_at);
                })
                .filter(ms => ms > 0);
            const avgDelivery = deliveryDurations.length ? deliveryDurations.reduce((a, b) => a + b, 0) / deliveryDurations.length : null;

            const budgetDurations = filteredTickets
                .filter(t => t.created_at && t.budget_sent_at)
                .map(t => new Date(t.budget_sent_at) - new Date(t.created_at))
                .filter(ms => ms > 0);
            const avgBudget = budgetDurations.length ? budgetDurations.reduce((a, b) => a + b, 0) / budgetDurations.length : null;

            const pickupDurations = filteredTickets
                .filter(t => t.created_at && t.pickup_available_at)
                .map(t => new Date(t.pickup_available_at) - new Date(t.created_at))
                .filter(ms => ms > 0);
            const avgPickupNotify = pickupDurations.length ? pickupDurations.reduce((a, b) => a + b, 0) / pickupDurations.length : null;

            const analysisCount = filteredTickets.filter(t => t.status === 'Analise Tecnica').length;
            const repairCount = filteredTickets.filter(t => t.status === 'Andamento Reparo').length;

            const defectsMap = {};
            const modelsMap = {};
            const comboMap = {};
            const techDetailMap = {};

            // Logistics Stats
            const logisticsStats = {
                pickup: { total: 0, success: 0, fail: 0 },
                carrier: { total: 0, success: 0, fail: 0 }
            };

            // Outsourced Stats (NEW)
            const outsourcedStats = {
                total: 0,
                internal: 0,
                success: 0,
                fail: 0,
                returnCount: 0
            };

            filteredTickets.forEach(ticket => {
                // Outsourced Stats logic
                if (ticket.is_outsourced) {
                    outsourcedStats.total++;
                    if (ticket.outsourced_return_count) outsourcedStats.returnCount += ticket.outsourced_return_count;

                    // Assuming Success/Fail logic applies if finalized?
                    // "taxa de sucesso da empresa tercerizada"
                    // If ticket.repair_successful is set, we count it
                    if (ticket.repair_successful === true) outsourcedStats.success++;
                    if (ticket.repair_successful === false) outsourcedStats.fail++;
                } else if (ticket.status === 'Finalizado' || ticket.repair_start_at) {
                    // Approximate internal check
                    outsourcedStats.internal++;
                }

                // ... (Existing loops for maps) ...
                if (ticket.delivery_method === 'pickup') {
                    logisticsStats.pickup.total++;
                    if (ticket.repair_successful === true) logisticsStats.pickup.success++;
                    if (ticket.repair_successful === false) logisticsStats.pickup.fail++;
                }
                if (ticket.delivery_method === 'carrier') {
                    logisticsStats.carrier.total++;
                    if (ticket.repair_successful === true) logisticsStats.carrier.success++;
                    if (ticket.repair_successful === false) logisticsStats.carrier.fail++;
                }

                if (ticket.device_model) {
                    if (!modelsMap[ticket.device_model]) modelsMap[ticket.device_model] = { total: 0, success: 0, fail: 0 };
                    modelsMap[ticket.device_model].total++;
                    if (ticket.repair_successful === true) modelsMap[ticket.device_model].success++;
                    if (ticket.repair_successful === false) modelsMap[ticket.device_model].fail++;
                }

                const defects = this.getDefectList(ticket.defect_reported);
                defects.forEach(defect => {
                    if (!defectsMap[defect]) defectsMap[defect] = { total: 0, success: 0, fail: 0 };
                    defectsMap[defect].total++;
                    if (ticket.repair_successful === true) defectsMap[defect].success++;
                    if (ticket.repair_successful === false) defectsMap[defect].fail++;

                    if (ticket.device_model) {
                        const comboKey = `${ticket.device_model} · ${defect}`;
                        if (!comboMap[comboKey]) comboMap[comboKey] = { total: 0, success: 0, fail: 0 };
                        comboMap[comboKey].total++;
                         if (ticket.repair_successful === true) comboMap[comboKey].success++;
                        if (ticket.repair_successful === false) comboMap[comboKey].fail++;
                    }

                    if (ticket.technician_id) {
                        if (!techDetailMap[ticket.technician_id]) {
                            techDetailMap[ticket.technician_id] = {
                                name: this.getEmployeeName(ticket.technician_id),
                                failureCounts: {},
                                successCounts: {}
                            };
                        }
                        const techStats = techDetailMap[ticket.technician_id];
                        if (ticket.repair_successful === false) {
                            const key = `${ticket.device_model} - ${defect}`;
                            techStats.failureCounts[key] = (techStats.failureCounts[key] || 0) + 1;
                        }
                        if (ticket.repair_successful === true) {
                            const key = `${ticket.device_model} - ${defect}`;
                            techStats.successCounts[key] = (techStats.successCounts[key] || 0) + 1;
                        }
                    }
                });
            });

            // ... (Rest of metric calculations, identical to before) ...
            const enhanceStats = (list) => list.map(item => {
                const total = item.total || 0;
                const success = item.success || 0;
                const fail = item.fail || 0;
                return {
                    ...item,
                    total: total,
                    success: success,
                    fail: fail,
                    successRate: total > 0 ? Math.round((success / total) * 100) : 0,
                    failRate: total > 0 ? Math.round((fail / total) * 100) : 0
                };
            });

            let topDefects = enhanceStats(this.getTopItems(defectsMap, 100));
            const field = this.adminDashboardFilters.defectSortField;
            const desc = this.adminDashboardFilters.defectSortDesc;
            topDefects.sort((a, b) => {
                const valA = a[field] || 0;
                const valB = b[field] || 0;
                return desc ? valB - valA : valA - valB;
            });

            const allModels = enhanceStats(this.getTopItems(modelsMap, 100));
            const topModels = this.adminDashboardFilters.viewMode === 'success_drilldown' ? allModels : allModels.slice(0, 4);
            const topCombos = enhanceStats(this.getTopItems(comboMap, 50));

            const techDeepDive = Object.values(techDetailMap).map(t => {
                const topFail = Object.entries(t.failureCounts).sort((a,b) => b[1]-a[1])[0];
                const topSuccess = Object.entries(t.successCounts).sort((a,b) => b[1]-a[1])[0];
                return {
                    name: t.name,
                    mostFrequentFail: topFail ? `${topFail[0]} (${topFail[1]})` : 'Nenhum',
                    mostFrequentSuccess: topSuccess ? `${topSuccess[0]} (${topSuccess[1]})` : 'Nenhum'
                };
            });

            const metricsMap = {
                repair: { model: {}, defect: {}, combo: {}, tech: {} },
                solution: { model: {}, defect: {}, combo: {}, tech: {} },
                delivery: { model: {}, defect: {}, combo: {}, tech: {} }
            };

            const accTime = (category, type, key, duration, techId) => {
                const target = metricsMap[category][type];
                if (!target[key]) target[key] = { totalTime: 0, count: 0 };
                target[key].totalTime += duration;
                target[key].count++;
            };

            const initTech = (category, techId) => {
                const target = metricsMap[category].tech;
                if (!target[techId]) target[techId] = { totalTime: 0, count: 0, successCount: 0, totalTickets: 0 };
                return target[techId];
            };

            filteredTickets.forEach(t => {
                const defectList = this.getDefectList(t.defect_reported);
                const techId = t.technician_id;

                if (t.repair_start_at && t.repair_end_at) {
                    const duration = new Date(t.repair_end_at) - new Date(t.repair_start_at);
                    if (duration > 0) {
                        accTime('repair', 'model', t.device_model, duration);
                        defectList.forEach(d => {
                            accTime('repair', 'defect', d, duration);
                            accTime('repair', 'combo', `${t.device_model} - ${d}`, duration);
                        });
                        if (techId) {
                            initTech('repair', techId).totalTime += duration;
                            initTech('repair', techId).count++;
                        }
                    }
                }

                if (t.created_at) {
                    const readyAt = t.pickup_available_at || t.repair_end_at;
                    if (readyAt) {
                        const duration = new Date(readyAt) - new Date(t.created_at);
                        if (duration > 0) {
                            accTime('solution', 'model', t.device_model, duration);
                            defectList.forEach(d => {
                                accTime('solution', 'defect', d, duration);
                                accTime('solution', 'combo', `${t.device_model} - ${d}`, duration);
                            });
                            if (techId) {
                                initTech('solution', techId).totalTime += duration;
                                initTech('solution', techId).count++;
                            }
                        }
                    }
                }

                if (t.created_at && t.delivered_at) {
                    const duration = new Date(t.delivered_at) - new Date(t.created_at);
                    if (duration > 0) {
                        accTime('delivery', 'model', t.device_model, duration);
                        defectList.forEach(d => {
                            accTime('delivery', 'defect', d, duration);
                            accTime('delivery', 'combo', `${t.device_model} - ${d}`, duration);
                        });
                        if (techId) {
                            initTech('delivery', techId).totalTime += duration;
                            initTech('delivery', techId).count++;
                        }
                    }
                }

                if (techId) {
                    ['repair', 'solution', 'delivery'].forEach(cat => {
                        const stats = initTech(cat, techId);
                        stats.totalTickets++;
                        if (t.repair_successful) stats.successCount++;
                    });
                }
            });

            const processTimes = (map, limit, sortDesc = true) => {
                return Object.entries(map)
                    .map(([label, stats]) => ({
                        label,
                        avgTime: stats.count ? stats.totalTime / stats.count : 0,
                        count: stats.count
                    }))
                    .sort((a, b) => sortDesc ? b.avgTime - a.avgTime : a.avgTime - b.avgTime)
                    .slice(0, limit);
            };

            const processTechs = (map) => {
                return Object.entries(map)
                    .map(([id, stats]) => ({
                        name: this.getEmployeeName(id),
                        avgTime: stats.count ? stats.totalTime / stats.count : 0,
                        successRate: stats.totalTickets ? Math.round((stats.successCount / stats.totalTickets) * 100) : 0,
                        count: stats.count
                    }))
                    .filter(t => t.avgTime > 0)
                    .sort((a, b) => a.avgTime - b.avgTime);
            };

            const slowestModels = processTimes(metricsMap.repair.model, 5, true);
            const slowestDefects = processTimes(metricsMap.repair.defect, 5, true);
            const slowestCombos = processTimes(metricsMap.repair.combo, 5, true);
            const fastestTechs = processTechs(metricsMap.repair.tech);

            const slowestModelsSolution = processTimes(metricsMap.solution.model, 5, true);
            const slowestDefectsSolution = processTimes(metricsMap.solution.defect, 5, true);
            const slowestCombosSolution = processTimes(metricsMap.solution.combo, 5, true);
            const fastestTechsSolution = processTechs(metricsMap.solution.tech);

            const slowestModelsDelivery = processTimes(metricsMap.delivery.model, 5, true);
            const slowestDefectsDelivery = processTimes(metricsMap.delivery.defect, 5, true);
            const slowestCombosDelivery = processTimes(metricsMap.delivery.combo, 5, true);
            const fastestTechsDelivery = processTechs(metricsMap.delivery.tech);

            const ticketsPerDay = Math.round(filteredTickets.length / rangeDays);

            const now = new Date();
            const oneDayAgo = new Date(now);
            oneDayAgo.setDate(now.getDate() - 1);
            const oneWeekAgo = new Date(now);
            oneWeekAgo.setDate(now.getDate() - 7);
            const oneMonthAgo = new Date(now);
            oneMonthAgo.setDate(now.getDate() - 30);

            const getRepairTimestamp = ticket => {
                if (ticket.repair_end_at) return new Date(ticket.repair_end_at);
                if (ticket.status === 'Finalizado' && ticket.updated_at) return new Date(ticket.updated_at);
                return null;
            };

            const repairsToday = filteredTickets.filter(t => {
                const timestamp = getRepairTimestamp(t);
                return timestamp && timestamp >= oneDayAgo;
            }).length;

            const repairsWeek = filteredTickets.filter(t => {
                const timestamp = getRepairTimestamp(t);
                return timestamp && timestamp >= oneWeekAgo;
            }).length;

            const repairsMonth = filteredTickets.filter(t => {
                const timestamp = getRepairTimestamp(t);
                return timestamp && timestamp >= oneMonthAgo;
            }).length;

            const ticketsToday = filteredTickets.filter(t => new Date(t.created_at) >= oneDayAgo).length;
            const ticketsWeek = filteredTickets.filter(t => new Date(t.created_at) >= oneWeekAgo).length;
            const ticketsMonth = filteredTickets.filter(t => new Date(t.created_at) >= oneMonthAgo).length;

            const techMap = {};
            filteredTickets.forEach(ticket => {
                const techId = ticket.technician_id || 'unassigned';
                if (!techMap[techId]) {
                    techMap[techId] = { totalAssigned: 0, completedCount: 0, successCount: 0 };
                }
                techMap[techId].totalAssigned += 1;

                if (ticket.repair_successful !== null && ticket.repair_successful !== undefined) {
                    techMap[techId].completedCount += 1;
                    if (ticket.repair_successful) {
                        techMap[techId].successCount += 1;
                    }
                }
            });

            const techStats = Object.entries(techMap)
                .map(([techId, data]) => {
                    const tech = this.employees.find(emp => emp.id == techId);
                    const name = tech ? tech.name : techId === 'unassigned' ? 'Sem técnico' : 'Técnico';
                    const rate = data.completedCount > 0 ? Math.round((data.successCount / data.completedCount) * 100) : 0;

                    return {
                        id: techId,
                        name,
                        total: data.totalAssigned,
                        completed: data.completedCount,
                        successRate: rate
                    };
                })
                .sort((a, b) => b.completed - a.completed);

            return {
                filteredTickets,
                rangeDays,
                successRate,
                avgRepair,
                avgSolution,
                avgDelivery,
                avgBudget,
                avgPickupNotify,
                analysisCount: analysisCount,
                repairCount: repairCount,
                analysisPerDay: Math.round(analysisCount / rangeDays),
                repairPerDay: Math.round(repairCount / rangeDays),
                ticketsPerDay,
                repairsToday,
                repairsWeek,
                repairsMonth,
                ticketsToday,
                ticketsWeek,
                ticketsMonth,
                topDefects,
                topModels,
                topCombos,
                techStats,
                techDeepDive,
                slowestModels, slowestDefects, slowestCombos, fastestTechs,
                slowestModelsSolution, slowestDefectsSolution, slowestCombosSolution, fastestTechsSolution,
                slowestModelsDelivery, slowestDefectsDelivery, slowestCombosDelivery, fastestTechsDelivery,
                logisticsStats,
                outsourcedStats // NEW
            };
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
