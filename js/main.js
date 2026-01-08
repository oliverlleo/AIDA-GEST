
// Configuração do Supabase
const SUPABASE_URL = 'https://cpydazjwlmssbzzsurxu.supabase.co';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNweWRhemp3bG1zc2J6enN1cnh1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc4Mjg5MTUsImV4cCI6MjA4MzQwNDkxNX0.NM7cuB6mks74ZzfvMYhluIjnqBXVgtolHbN4huKmE-Q';

// Variável Global do Client
let supabaseClient;

// Função Factory para criar o Client (Permite recriação forçada)
function initSupabaseClient() {
    try {
        return window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY, {
            auth: {
                persistSession: true,
                autoRefreshToken: true,
                detectSessionInUrl: false
            },
            realtime: {
                params: {
                    eventsPerSecond: 10,
                },
            },
        });
    } catch (e) {
        console.error("Supabase init fail:", e);
        return null;
    }
}

// Inicialização inicial
supabaseClient = initSupabaseClient();

function app() {
    return {
        // State
        loading: false,
        session: null,
        employeeSession: null,
        user: null,
        workspaceName: '',
        companyCode: '',
        registrationSuccess: false,
        newCompanyCode: '',
        view: 'dashboard',
        authMode: 'employee',

        // Data
        employees: [],
        tickets: [],
        techTickets: [],
        checklistTemplates: [],
        notifications: [],

        // Forms
        loginForm: { company_code: '', username: '', password: '' },
        adminForm: { email: '', password: '' },
        registerForm: { companyName: '', email: '', password: '' },
        employeeForm: { name: '', username: '', password: '', roles: [] },

        // Ticket Form
        ticketForm: {
            client_name: '', os_number: '', model: '', serial: '',
            defect: '', priority: 'Normal', contact: '',
            deadline: '', device_condition: '',
            checklist: [], photos: [], notes: ''
        },
        newChecklistItem: '',
        selectedTemplateId: '',
        newTemplateName: '',

        // UI State for Actions
        analysisForm: { needsParts: false, partsList: '' },
        outcomeMode: '', // 'repair' or 'test'
        showTestFailureForm: false,
        testFailureData: { newDeadline: '', newPriority: 'Normal' },

        // Selected Ticket
        selectedTicket: null,
        modalSource: '', // 'kanban' or 'tech'

        // Time
        currentTime: new Date(),

        // Modals
        modals: { newEmployee: false, ticket: false, viewTicket: false, outcome: false },

        // Constants
        PRIORITIES: ['Baixa', 'Normal', 'Alta', 'Urgente'],
        STATUS_COLUMNS: [
            'Aberto', 'Analise Tecnica', 'Aprovacao', 'Compra Peca',
            'Andamento Reparo', 'Teste Final', 'Retirada Cliente', 'Finalizado'
        ],

        async init() {
            console.log("App initializing...");
            this.loading = true;

            if (!supabaseClient) {
                this.notify("Erro crítico: Supabase não carregou.", "error");
                this.loading = false;
                return;
            }

            try {
                // Initial Session Check
                const { data: { session } } = await supabaseClient.auth.getSession();
                if (session) {
                    this.session = session;
                    await this.loadAdminData();
                } else {
                    // Try Employee Session from LocalStorage
                    const storedEmp = localStorage.getItem('techassist_employee');
                    if (storedEmp) {
                        try {
                            this.employeeSession = JSON.parse(storedEmp);
                            this.user = this.employeeSession;
                            if (this.employeeSession.workspace_name) this.workspaceName = this.employeeSession.workspace_name;
                            if (this.employeeSession.company_code) this.companyCode = this.employeeSession.company_code;
                            await this.fetchEmployees();
                        } catch (e) {
                            localStorage.removeItem('techassist_employee');
                        }
                    }
                }

                if (this.user) {
                    await this.fetchTickets();
                    await this.fetchTemplates();
                    this.setupRealtime();
                }
            } catch (err) {
                console.error("Init Error:", err);
            } finally {
                this.loading = false;
            }

            // Auth State Listener (Global)
            this.setupAuthListener();

            // Clock Interval
            setInterval(() => {
                this.currentTime = new Date();
            }, 1000);

            // --- STRATEGY: HARD RESET ON WAKE UP ---
            // Detecta quando a aba volta a ser visível, mata o cliente velho e cria um novo.
            // Isso simula o comportamento de "Refresh" da página, garantindo conexão limpa.
            let visibilityTimer;
            document.addEventListener("visibilitychange", () => {
                if (document.visibilityState === 'visible') {
                    clearTimeout(visibilityTimer);
                    // Espera um momento para o navegador "acordar" a pilha de rede
                    visibilityTimer = setTimeout(async () => {
                        console.log("Tab visible. Performing Hard Client Reset...");

                        // 1. Desconecta tudo do cliente velho (evita leaks)
                        if (supabaseClient) {
                            await supabaseClient.removeAllChannels();
                        }

                        // 2. RECIA o cliente do zero (Nova conexão limpa)
                        supabaseClient = initSupabaseClient();

                        // 3. Re-ata o listener de Auth no novo cliente
                        this.setupAuthListener();

                        // 4. Restaura Sessão e Dados
                        // O novo cliente lerá o localStorage automaticamente (persistSession)
                        const { data: { session } } = await supabaseClient.auth.getSession();
                        if (session) {
                            this.session = session;
                        }

                        // 5. Busca dados e reconecta Realtime
                        if (this.user) {
                            await this.fetchTickets();
                            this.setupRealtime();
                        }

                    }, 500);
                } else {
                    // Se ocultou a aba, já podemos matar os canais para economizar e evitar erros ao voltar
                     if (supabaseClient) {
                         supabaseClient.removeAllChannels();
                     }
                }
            });
        },

        setupAuthListener() {
            if (!supabaseClient) return;
            supabaseClient.auth.onAuthStateChange(async (_event, session) => {
                this.session = session;
                if (session) {
                    await this.loadAdminData();
                } else if (!this.employeeSession) {
                    this.user = null;
                }
            });
        },

        setupRealtime() {
            if (!this.user?.workspace_id || !supabaseClient) return;

            // Remove canais antigos caso existam (prevenção extra)
            supabaseClient.getChannels().forEach(c => supabaseClient.removeChannel(c));

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
                 const { data: wsId, error: wsError } = await supabaseClient
                    .rpc('create_owner_workspace_and_profile', {
                        p_name: this.registerForm.companyName,
                        p_company_code: generatedCode
                    });
                if (wsError) {
                    console.error(wsError);
                    this.notify('Erro: ' + wsError.message, 'error');
                } else {
                    this.newCompanyCode = generatedCode;
                    this.registrationSuccess = true;
                    this.notify('Conta criada!', 'success');
                }
             } finally {
                 this.loading = false;
             }
        },
        async loginEmployee() {
            this.loading = true;
            try {
                const { data, error } = await supabaseClient
                    .rpc('employee_login', {
                        p_company_code: this.loginForm.company_code,
                        p_username: this.loginForm.username,
                        p_password: this.loginForm.password
                    });
                if (error) {
                    this.notify('Falha no login.', 'error');
                } else if (data && data.length > 0) {
                    const emp = data[0];
                    this.employeeSession = emp;
                    this.user = emp;
                    this.workspaceName = emp.workspace_name;
                    this.companyCode = emp.company_code;
                    localStorage.setItem('techassist_employee', JSON.stringify(emp));
                    this.notify('Bem-vindo, ' + emp.name, 'success');
                    await this.fetchEmployees();
                    await this.fetchTickets();
                    await this.fetchTemplates();
                    this.setupRealtime();
                } else {
                     this.notify('Credenciais inválidas.', 'error');
                }
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
            localStorage.removeItem('techassist_employee');
            this.view = 'dashboard';
            this.loading = false;
            window.location.reload();
        },
        async loadAdminData() {
            if (!this.session) return;
            const user = this.session.user;
            let { data: profile, error } = await supabaseClient
                .from('profiles')
                .select('*, workspaces(name, company_code)')
                .eq('id', user.id)
                .single();
            if (error && error.code === 'PGRST116') {
                const { data: wsData } = await supabaseClient
                    .from('workspaces').select('id, name, company_code').eq('owner_id', user.id).single();
                if (wsData) {
                    await supabaseClient.from('profiles').insert([{ id: user.id, workspace_id: wsData.id, role: 'admin' }]);
                    profile = (await supabaseClient.from('profiles').select('*, workspaces(name, company_code)').eq('id', user.id).single()).data;
                } else {
                    this.view = 'setup_required';
                    return;
                }
            }
            if (profile) {
                this.user = { id: user.id, email: user.email, name: 'Administrador', roles: ['admin'], workspace_id: profile.workspace_id };
                this.workspaceName = profile.workspaces?.name;
                this.companyCode = profile.workspaces?.company_code;
                await this.fetchEmployees();
                await this.fetchTickets();
                await this.fetchTemplates();
                this.setupRealtime();
            }
        },
        async fetchEmployees() {
            if (!this.user?.workspace_id) return;
            let result;
            if (this.session) {
                result = await supabaseClient.from('employees').select('*').eq('workspace_id', this.user.workspace_id).order('created_at', { ascending: false });
            } else {
                result = await supabaseClient.rpc('get_employees_for_workspace', { p_workspace_id: this.user.workspace_id });
            }
            if (!result.error) this.employees = result.data;
        },

        // --- TICKET LOGIC ---

        async fetchTickets(retryCount = 0) {
            if (!this.user?.workspace_id) return;

            try {
                const { data, error } = await supabaseClient
                    .from('tickets')
                    .select('*')
                    .eq('workspace_id', this.user.workspace_id)
                    .order('created_at', { ascending: false });

                if (error) {
                    if (error.message && (error.message.includes('AbortError') || error.message.includes('signal is aborted') || error.message.includes('Failed to fetch'))) {
                        if (retryCount < 2) {
                            setTimeout(() => this.fetchTickets(retryCount + 1), 1000);
                        }
                        return;
                    }
                    if (error.code === 'PGRST205') {
                        this.tickets = [];
                        this.techTickets = [];
                        return;
                    }
                    console.error("Error fetching tickets:", error);
                    return;
                }

                if (data) {
                    this.tickets = data;
                    this.techTickets = data.filter(t =>
                        ['Analise Tecnica', 'Andamento Reparo'].includes(t.status)
                    ).sort((a, b) => {
                        const pOrder = { 'Urgente': 0, 'Alta': 1, 'Normal': 2, 'Baixa': 3 };
                        const pDiff = pOrder[a.priority] - pOrder[b.priority];
                        if (pDiff !== 0) return pDiff;
                        return new Date(a.deadline || 0) - new Date(b.deadline || 0);
                    });
                }
            } catch (err) {
                 console.warn("Fetch exception:", err);
            }
        },

        async fetchTemplates() {
             if (!this.user?.workspace_id) return;
             const { data } = await supabaseClient.from('checklist_templates').select('*');
             if (data) this.checklistTemplates = data;
        },

        openNewTicketModal() {
            this.ticketForm = {
                client_name: '', os_number: '', model: '', serial: '',
                defect: '', priority: 'Normal', contact: '',
                deadline: '', device_condition: '',
                checklist: [], photos: [], notes: ''
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
            const { error } = await supabaseClient.from('checklist_templates').insert({
                workspace_id: this.user.workspace_id,
                name: this.newTemplateName,
                items: this.ticketForm.checklist.map(i => i.item)
            });
            if (error) this.notify("Erro ao salvar", "error");
            else {
                this.notify("Modelo salvo!");
                this.newTemplateName = '';
                this.fetchTemplates();
            }
        },
        loadTemplate() {
            const tmpl = this.checklistTemplates.find(t => t.id === this.selectedTemplateId);
            if (tmpl) this.ticketForm.checklist = tmpl.items.map(s => ({ item: s, ok: false }));
        },

        async createTicket() {
             if (!this.ticketForm.client_name || !this.ticketForm.os_number || !this.ticketForm.model) {
                 return this.notify("Preencha os campos obrigatórios (*)", "error");
             }
             this.loading = true;
             try {
                 const ticketData = {
                     workspace_id: this.user.workspace_id,
                     client_name: this.ticketForm.client_name,
                     os_number: this.ticketForm.os_number,
                     device_model: this.ticketForm.model,
                     serial_number: this.ticketForm.serial,
                     defect_reported: this.ticketForm.defect,
                     priority: this.ticketForm.priority,
                     contact_info: this.ticketForm.contact,
                     deadline: this.ticketForm.deadline || null,
                     device_condition: this.ticketForm.device_condition,
                     checklist_data: this.ticketForm.checklist,
                     status: 'Aberto',
                     created_by_name: this.user.name
                 };

                 const { error } = await supabaseClient.from('tickets').insert(ticketData);

                 if (error) {
                     console.error(error);
                     this.notify("Erro ao criar chamado.", "error");
                 } else {
                     this.notify("Chamado criado!");
                     this.modals.ticket = false;
                     await this.fetchTickets();
                 }
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
            // Reset UI states
            this.analysisForm = { needsParts: !!ticket.parts_needed, partsList: ticket.parts_needed || '' };
            this.modals.viewTicket = true;
        },

        // --- WORKFLOW ACTIONS ---

        async updateStatus(ticket, newStatus, additionalUpdates = {}) {
            this.loading = true;
            try {
                // Log action
                await supabaseClient.from('ticket_logs').insert({
                    ticket_id: ticket.id,
                    action: 'Alteração de Status',
                    details: `De ${ticket.status} para ${newStatus}`,
                    user_name: this.user.name
                });

                const updates = { status: newStatus, ...additionalUpdates };
                const { error } = await supabaseClient.from('tickets').update(updates).eq('id', ticket.id);

                if (error) throw error;

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

        async finishAnalysis() {
            if (this.analysisForm.needsParts && !this.analysisForm.partsList) {
                return this.notify("Liste as peças necessárias.", "error");
            }
            await this.updateStatus(this.selectedTicket, 'Aprovacao', {
                parts_needed: this.analysisForm.partsList,
                tech_notes: this.selectedTicket.tech_notes
            });
        },

        async sendBudget(ticket = this.selectedTicket) {
            this.loading = true;
            try {
                const { error } = await supabaseClient.from('tickets').update({
                    budget_status: 'Enviado',
                    budget_sent_at: new Date().toISOString()
                }).eq('id', ticket.id);

                if (!error) {
                    if (this.selectedTicket && this.selectedTicket.id === ticket.id) {
                        this.selectedTicket = { ...this.selectedTicket, budget_status: 'Enviado' };
                    }
                    this.notify("Orçamento marcado como Enviado.");
                    await this.fetchTickets();
                } else {
                    this.notify("Erro: " + error.message, "error");
                }
            } finally {
                this.loading = false;
            }
        },
        async approveRepair(ticket = this.selectedTicket) {
            const nextStatus = ticket.parts_needed ? 'Compra Peca' : 'Andamento Reparo';
            await this.updateStatus(ticket, nextStatus, { budget_status: 'Aprovado' });
        },
        async denyRepair(ticket = this.selectedTicket) {
             await this.updateStatus(ticket, 'Retirada Cliente', { budget_status: 'Negado', repair_successful: false });
        },

        async markPurchased(ticket = this.selectedTicket) {
             this.loading = true;
             try {
                 await supabaseClient.from('tickets').update({
                    parts_status: 'Comprado',
                    parts_purchased_at: new Date().toISOString()
                }).eq('id', ticket.id);
                await this.fetchTickets();
             } finally {
                this.loading = false;
             }
        },
        async confirmReceived(ticket = this.selectedTicket) {
             await this.updateStatus(ticket, 'Andamento Reparo', {
                 parts_status: 'Recebido',
                 parts_received_at: new Date().toISOString()
             });
        },

        async startRepair(ticket = this.selectedTicket) {
             this.loading = true;
             try {
                 const now = new Date().toISOString();
                 await supabaseClient.from('tickets').update({
                    repair_start_at: now
                }).eq('id', ticket.id);

                if (this.selectedTicket && this.selectedTicket.id === ticket.id) {
                    this.selectedTicket = { ...this.selectedTicket, repair_start_at: now };
                }
                await this.fetchTickets();
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
            this.modals.outcome = false;
            await this.updateStatus(ticket, nextStatus, updates);
        },

        async startTest(ticket = this.selectedTicket) {
             this.loading = true;
             try {
                 await supabaseClient.from('tickets').update({
                    test_start_at: new Date().toISOString()
                }).eq('id', ticket.id);
                await this.fetchTickets();
             } finally {
                this.loading = false;
             }
        },

        async concludeTest(success) {
            const ticket = this.selectedTicket;
            if (success) {
                this.modals.outcome = false;
                await this.updateStatus(ticket, 'Retirada Cliente');
            } else {
                if (!this.testFailureData.newDeadline) return this.notify("Defina um novo prazo", "error");

                this.modals.outcome = false;
                await this.updateStatus(ticket, 'Analise Tecnica', {
                    deadline: this.testFailureData.newDeadline,
                    priority: this.testFailureData.newPriority,
                    repair_start_at: null,
                    test_start_at: null,
                    status: 'Analise Tecnica'
                });
                this.notify("Retornado para bancada com urgência!");
            }
        },

        async markAvailable(ticket = this.selectedTicket) {
             this.loading = true;
             try {
                 await supabaseClient.from('tickets').update({
                    pickup_available: true,
                    pickup_available_at: new Date().toISOString()
                }).eq('id', ticket.id);
                await this.fetchTickets();
             } finally {
                this.loading = false;
             }
        },
        async confirmPickup(ticket = this.selectedTicket) {
            await this.updateStatus(ticket, 'Finalizado');
        },

        // --- UTILS ---
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

        openModal(name) {
            this.employeeForm = { name: '', username: '', password: '', roles: [] };
            this.modals[name] = true;
        },

        async createEmployee() {
            if (!this.user?.workspace_id) return this.notify('Erro workspace', 'error');
            if (!this.employeeForm.name || !this.employeeForm.username || !this.employeeForm.password) return this.notify('Preencha campos', 'error');
            this.loading = true;
            try {
                const { error } = await supabaseClient.rpc('create_employee', {
                    p_workspace_id: this.user.workspace_id,
                    p_name: this.employeeForm.name,
                    p_username: this.employeeForm.username,
                    p_password: this.employeeForm.password,
                    p_roles: this.employeeForm.roles
                });
                if (error) {
                    console.error(error);
                    this.notify('Erro: ' + error.message, 'error');
                } else {
                    this.notify('Criado!');
                    this.modals.newEmployee = false;
                    await this.fetchEmployees();
                }
            } finally {
                this.loading = false;
            }
        },

        async deleteEmployee(id) {
            if (!confirm('Confirma?')) return;
            const { error } = await supabaseClient.from('employees').delete().eq('id', id);
            if (error) this.notify('Erro.', 'error'); else { this.notify('Excluído.'); this.fetchEmployees(); }
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
