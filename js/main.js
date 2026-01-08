
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
            technician_id: '', // New field
            checklist: [], photos: [], notes: ''
        },
        newChecklistItem: '',
        selectedTemplateId: '',
        newTemplateName: '',

        // UI State for Actions
        analysisForm: { needsParts: false, partsList: '' },
        outcomeMode: '', // 'repair' or 'test'
        showTestFailureForm: false,
        testFailureData: { newDeadline: '', newPriority: 'Normal', reason: '' },

        // Selected Ticket
        selectedTicket: null,
        ticketLogs: [],
        logViewMode: 'timeline', // 'timeline' or 'detailed'
        modalSource: '', // 'kanban' or 'tech'

        // Calendar State
        calendarView: 'week',
        currentCalendarDate: new Date(),
        showAllCalendarTickets: false,
        selectedTechFilter: 'all', // 'all' or specific uuid

        // Time
        currentTime: new Date(),

        // Modals
        modals: { newEmployee: false, ticket: false, viewTicket: false, outcome: false, logs: false, calendar: false },

        // Constants
        PRIORITIES: ['Baixa', 'Normal', 'Alta', 'Urgente'],
        STATUS_COLUMNS: [
            'Aberto', 'Analise Tecnica', 'Aprovacao', 'Compra Peca',
            'Andamento Reparo', 'Teste Final', 'Retirada Cliente', 'Finalizado'
        ],
        STATUS_LABELS: {
            'Aberto': 'Aberto',
            'Analise Tecnica': 'Análise Técnica',
            'Aprovacao': 'Aprovação',
            'Compra Peca': 'Compra de Peças',
            'Andamento Reparo': 'Em Reparo',
            'Teste Final': 'Testes Finais',
            'Retirada Cliente': 'Retirada de Cliente',
            'Finalizado': 'Finalizado'
        },

        // --- HELPER: NATIVE FETCH (Stateless) ---
        // Bypasses supabase-js lock management to avoid AbortError on tab wake
        async supabaseFetch(endpoint, method = 'GET', body = null) {
            const isRpc = endpoint.startsWith('rpc/');
            const url = `${SUPABASE_URL}/rest/v1/${endpoint}`;

            // Determine Auth Token
            // If Admin (session exists), use Access Token.
            // If Employee (no session, just local state), use Anon Key (RLS allows specific access).
            // If Login/Public, use Anon Key.
            let token = SUPABASE_KEY;
            if (this.session && this.session.access_token) {
                token = this.session.access_token;
            }

            const headers = {
                'apikey': SUPABASE_KEY,
                'Authorization': `Bearer ${token}`,
                'Content-Type': 'application/json',
                // Preferences for minimal response or representation
                'Prefer': method === 'GET' ? undefined : 'return=representation'
            };

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

            // For void responses (204)
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

                            // Normalize ID if loaded from old storage format
                            if (this.employeeSession.employee_id && !this.employeeSession.id) {
                                this.employeeSession.id = this.employeeSession.employee_id;
                            }

                            this.user = this.employeeSession;
                            if (this.employeeSession.workspace_name) this.workspaceName = this.employeeSession.workspace_name;
                            if (this.employeeSession.company_code) this.companyCode = this.employeeSession.company_code;
                            await this.fetchEmployees();
                            this.initTechFilter(); // Initialize filter on restore
                        } catch (e) {
                            localStorage.removeItem('techassist_employee');
                        }
                    }
                }

                if (this.user) {
                    this.initTechFilter(); // Ensure filter is set for Admin session restore too
                    await this.fetchTickets();
                    await this.fetchTemplates();
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

            // Removed visibilitychange listener to prevent lock conflicts.
            // Data is kept fresh via Realtime subscriptions.
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

                 // REFACTORED: Use Native Fetch for RPC
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
                // REFACTORED: Use Native Fetch for RPC
                const data = await this.supabaseFetch('rpc/employee_login', 'POST', {
                        p_company_code: this.loginForm.company_code,
                        p_username: this.loginForm.username,
                        p_password: this.loginForm.password
                });

                if (data && data.length > 0) {
                    const emp = data[0];

                    // Normalize ID (RPC returns employee_id)
                    if (emp.employee_id && !emp.id) {
                        emp.id = emp.employee_id;
                    }

                    this.employeeSession = emp;
                    this.user = emp;
                    this.workspaceName = emp.workspace_name; // Note: RPC might not return workspace_name directly, check this too
                    this.companyCode = this.loginForm.company_code; // Save from form input as RPC takes it but returns ID

                    localStorage.setItem('techassist_employee', JSON.stringify(emp));
                    this.notify('Bem-vindo, ' + emp.name, 'success');
                    await this.fetchEmployees();
                    this.initTechFilter(); // Initialize filter before fetching
                    await this.fetchTickets();
                    await this.fetchTemplates();

                    // Redirect Technician directly to Bench
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
            localStorage.removeItem('techassist_employee');
            this.view = 'dashboard';
            this.loading = false;
            window.location.reload();
        },
        async loadAdminData() {
            if (!this.session) return;
            const user = this.session.user;

            // REFACTORED: Native Fetch
            try {
                const profileData = await this.supabaseFetch(`profiles?select=*,workspaces(name,company_code)&id=eq.${user.id}`);
                let profile = profileData && profileData.length > 0 ? profileData[0] : null;

                // Handle missing profile case (equivalent to PGRST116)
                if (!profile) {
                    const wsData = await this.supabaseFetch(`workspaces?select=id,name,company_code&owner_id=eq.${user.id}`);
                    const workspace = wsData && wsData.length > 0 ? wsData[0] : null;

                    if (workspace) {
                        await this.supabaseFetch('profiles', 'POST', { id: user.id, workspace_id: workspace.id, role: 'admin' });
                        // Re-fetch
                        const newProfileData = await this.supabaseFetch(`profiles?select=*,workspaces(name,company_code)&id=eq.${user.id}`);
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
                    await this.fetchEmployees();
                    this.initTechFilter(); // Admin defaults to 'all'
                    await this.fetchTickets();
                    await this.fetchTemplates();
                    this.setupRealtime();
                }
            } catch (err) {
                console.error("Load Admin Error:", err);
            }
        },
        async fetchEmployees() {
            if (!this.user?.workspace_id) return;

            // REFACTORED: Native Fetch for ALL employee fetches
            try {
                let data;
                if (this.session) {
                     // Table Select
                     data = await this.supabaseFetch(`employees?select=*&workspace_id=eq.${this.user.workspace_id}&order=created_at.desc`);
                } else {
                     // RPC Call
                     data = await this.supabaseFetch('rpc/get_employees_for_workspace', 'POST', { p_workspace_id: this.user.workspace_id });
                }
                if (data) this.employees = data;
            } catch (e) {
                 console.error("Fetch Employees Error:", e);
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
            } catch (e) {
                console.error("Log failed:", e);
            }
        },

        async fetchTicketLogs(ticketId) {
            // Only admins can see logs
            if (!this.hasRole('admin')) return [];
            try {
                const logs = await this.supabaseFetch(`ticket_logs?ticket_id=eq.${ticketId}&order=created_at.desc`);
                return logs || [];
            } catch (e) {
                console.error("Fetch logs failed:", e);
                return [];
            }
        },

        async openLogs(ticket) {
            this.loading = true;
            try {
                this.ticketLogs = await this.fetchTicketLogs(ticket.id);
                this.logViewMode = 'timeline'; // Reset to default view
                this.modals.logs = true;
            } finally {
                this.loading = false;
            }
        },

        // --- TICKET LOGIC ---

        async fetchTickets(retryCount = 0) {
            if (!this.user?.workspace_id) return;

            try {
                // REFACTORED: Native Fetch
                const data = await this.supabaseFetch(
                    `tickets?select=*&workspace_id=eq.${this.user.workspace_id}&order=created_at.desc`
                );

                if (data) {
                    this.tickets = data;

                    // Apply Tech Filter to Minha Bancada
                    let filteredTechTickets = data;
                    let effectiveFilter = this.selectedTechFilter;

                    const isTechOnly = !this.hasRole('admin') && this.hasRole('tecnico');

                    // SAFETY: If pure technician, FORCE filter to self regardless of state
                    if (isTechOnly && this.user) {
                        effectiveFilter = this.user.id;
                        this.selectedTechFilter = this.user.id;
                    }

                    // Apply Filter
                    if (effectiveFilter && effectiveFilter !== 'all') {
                        // Use loose equality (==) to handle potential UUID type mismatches
                        filteredTechTickets = filteredTechTickets.filter(t => t.technician_id == effectiveFilter);
                    } else if (isTechOnly) {
                         // FAIL CLOSED: If user is Tech Only and filter is missing/invalid, SHOW NOTHING.
                         // Do NOT allow falling through to the full list.
                         console.warn("Tech View Security: Filter missing, hiding all tickets.");
                         filteredTechTickets = [];
                    }

                    this.techTickets = filteredTechTickets.filter(t =>
                        ['Analise Tecnica', 'Andamento Reparo'].includes(t.status)
                    ).sort((a, b) => {
                        // Priority Requested (Top of list)
                        if (a.priority_requested && !b.priority_requested) return -1;
                        if (!a.priority_requested && b.priority_requested) return 1;

                        // Standard Priority
                        const pOrder = { 'Urgente': 0, 'Alta': 1, 'Normal': 2, 'Baixa': 3 };
                        const pDiff = pOrder[a.priority] - pOrder[b.priority];
                        if (pDiff !== 0) return pDiff;

                        // Deadline
                        return new Date(a.deadline || 0) - new Date(b.deadline || 0);
                    });
                }
            } catch (err) {
                 console.warn("Fetch exception:", err);
                 // Retry logic for abort/fetch errors
                 if (retryCount < 2) {
                     setTimeout(() => this.fetchTickets(retryCount + 1), 1000);
                 } else {
                     // On final failure, empty lists to avoid stale state if desired, or keep old data.
                     // Choosing to keep old data to be less disruptive, but could clear.
                     console.error("Final ticket fetch failure");
                 }
            }
        },

        async fetchTemplates() {
             if (!this.user?.workspace_id) return;
             try {
                 // REFACTORED: Native Fetch
                 const data = await this.supabaseFetch('checklist_templates?select=*');
                 if (data) this.checklistTemplates = data;
             } catch (e) {
                 console.error("Fetch Templates Error:", e);
             }
        },

        openNewTicketModal() {
            this.ticketForm = {
                client_name: '', os_number: '', model: '', serial: '',
                defect: '', priority: 'Normal', contact: '',
                deadline: '', device_condition: '',
                technician_id: '',
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

            try {
                // REFACTORED: Native Fetch
                await this.supabaseFetch('checklist_templates', 'POST', {
                    workspace_id: this.user.workspace_id,
                    name: this.newTemplateName,
                    items: this.ticketForm.checklist.map(i => i.item)
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
                // REFACTORED: Native Fetch
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
                     technician_id: this.ticketForm.technician_id || null, // New Field
                     checklist_data: this.ticketForm.checklist,
                     status: 'Aberto',
                     created_by_name: this.user.name
                 };

                 // REFACTORED: Native Fetch
                 await this.supabaseFetch('tickets', 'POST', ticketData);

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
            // Reset UI states
            this.analysisForm = { needsParts: !!ticket.parts_needed, partsList: ticket.parts_needed || '' };
            this.modals.viewTicket = true;
        },

        // REFACTORED: Native Fetch Implementation
        async saveTicketChanges() {
             if (!this.selectedTicket) return;
             this.loading = true;
             try {
                 await this.supabaseFetch(`tickets?id=eq.${this.selectedTicket.id}`, 'PATCH', {
                     tech_notes: this.selectedTicket.tech_notes,
                     parts_needed: this.selectedTicket.parts_needed
                 });
                 this.notify("Anotações salvas!");
                 await this.fetchTickets();
             } catch (e) {
                 this.notify("Erro ao salvar: " + e.message, "error");
             } finally {
                 this.loading = false;
             }
        },

        // --- WORKFLOW ACTIONS ---

        async updateStatus(ticket, newStatus, additionalUpdates = {}, actionLog = null) {
            this.loading = true;
            try {
                // Default generic log if specific action not provided
                if (actionLog) {
                     await this.logTicketAction(ticket.id, actionLog.action, actionLog.details);
                } else {
                     await this.logTicketAction(ticket.id, 'Alteração de Status', `De ${ticket.status} para ${newStatus}`);
                }

                const updates = { status: newStatus, ...additionalUpdates };

                // REFACTORED: Native Fetch - Update Ticket
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

        async finishAnalysis() {
            if (this.analysisForm.needsParts && !this.analysisForm.partsList) {
                return this.notify("Liste as peças necessárias.", "error");
            }
            // Log Action: Finalizou Análise
            await this.updateStatus(this.selectedTicket, 'Aprovacao', {
                parts_needed: this.analysisForm.partsList,
                tech_notes: this.selectedTicket.tech_notes
            }, { action: 'Finalizou Análise', details: 'Enviado para Aprovação' });
        },

        openWhatsApp(phone) {
            if (!phone) return this.notify("Telefone não cadastrado.", "error");

            // Remove non-digits
            let number = phone.replace(/\D/g, '');

            // Basic validation/formatting
            if (number.length < 10) return this.notify("Número inválido para WhatsApp.", "error");

            // Prepend 55 if likely missing (assuming BR numbers usually start with DDD)
            // If it already starts with 55 and is long enough, leave it.
            // But simple heuristic: if length is 10 or 11 (DDD+Number), add 55.
            if (number.length <= 11) {
                number = '55' + number;
            }

            window.open(`https://wa.me/${number}`, '_blank');
        },

        async startBudget(ticket) {
            await this.logTicketAction(ticket.id, 'Iniciou Orçamento', 'Visualizou para criar orçamento');
            this.viewTicketDetails(ticket);
            this.openWhatsApp(ticket.contact_info);
        },

        async sendBudget(ticket = this.selectedTicket) {
            this.loading = true;
            try {
                // Log Action
                await this.logTicketAction(ticket.id, 'Enviou Orçamento', 'Orçamento marcado como enviado ao cliente');

                // REFACTORED: Native Fetch
                await this.supabaseFetch(`tickets?id=eq.${ticket.id}`, 'PATCH', {
                    budget_status: 'Enviado',
                    budget_sent_at: new Date().toISOString()
                });

                if (this.selectedTicket && this.selectedTicket.id === ticket.id) {
                    this.selectedTicket = { ...this.selectedTicket, budget_status: 'Enviado' };
                }
                this.notify("Orçamento marcado como Enviado.");
                await this.fetchTickets();
            } catch(e) {
                 this.notify("Erro: " + e.message, "error");
            } finally {
                this.loading = false;
            }
        },
        async approveRepair(ticket = this.selectedTicket) {
            const nextStatus = ticket.parts_needed ? 'Compra Peca' : 'Andamento Reparo';
            await this.updateStatus(ticket, nextStatus, { budget_status: 'Aprovado' }, { action: 'Aprovou Orçamento', details: 'Orçamento aprovado pelo cliente' });
        },
        async denyRepair(ticket = this.selectedTicket) {
             await this.updateStatus(ticket, 'Retirada Cliente', { budget_status: 'Negado', repair_successful: false }, { action: 'Negou Orçamento', details: 'Orçamento negado pelo cliente' });
        },

        async markPurchased(ticket = this.selectedTicket) {
             this.loading = true;
             try {
                 // Log Action
                 await this.logTicketAction(ticket.id, 'Confirmou Compra', 'Peças marcadas como compradas');

                 // REFACTORED: Native Fetch
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
             await this.updateStatus(ticket, 'Andamento Reparo', {
                 parts_status: 'Recebido',
                 parts_received_at: new Date().toISOString()
             }, { action: 'Recebeu Peças', details: 'Peças recebidas, iniciando reparo' });
        },

        async startRepair(ticket = this.selectedTicket) {
             this.loading = true;
             try {
                 // Log Action
                 await this.logTicketAction(ticket.id, 'Iniciou Reparo', 'Técnico iniciou a execução do reparo');

                 const now = new Date().toISOString();
                 // REFACTORED: Native Fetch
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

            this.modals.outcome = false;
            await this.updateStatus(ticket, nextStatus, updates, {
                action: 'Finalizou Reparo',
                details: `Resultado: ${success ? 'Sucesso' : 'Falha'}. Tempo de Reparo: ${duration}`
            });
        },

        async startTest(ticket = this.selectedTicket) {
             this.loading = true;
             try {
                 // Log Action
                 await this.logTicketAction(ticket.id, 'Iniciou Testes', 'Técnico iniciou bateria de testes');

                 const now = new Date().toISOString();
                 // REFACTORED: Native Fetch
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
            if (success) {
                this.modals.outcome = false;
                await this.updateStatus(ticket, 'Retirada Cliente', {}, { action: 'Concluiu Testes', details: 'Aparelho aprovado nos testes' });
            } else {
                if (!this.testFailureData.newDeadline) return this.notify("Defina um novo prazo", "error");
                if (!this.testFailureData.reason) return this.notify("Descreva o defeito apresentado", "error");

                // Prepare new note
                const newNote = {
                    date: new Date().toISOString(),
                    text: this.testFailureData.reason,
                    user: this.user.name
                };

                const existingNotes = Array.isArray(ticket.test_notes) ? ticket.test_notes : [];
                const updatedNotes = [...existingNotes, newNote];

                this.modals.outcome = false;
                await this.updateStatus(ticket, 'Andamento Reparo', {
                    deadline: this.testFailureData.newDeadline,
                    priority: this.testFailureData.newPriority,
                    repair_start_at: null, // Reset timer
                    test_start_at: null,
                    status: 'Andamento Reparo',
                    test_notes: updatedNotes
                }, { action: 'Reprovou Testes', details: 'Retornado para Reparo. Defeito: ' + this.testFailureData.reason });
                this.notify("Retornado para reparo com urgência!");
            }
        },

        async markAvailable(ticket = this.selectedTicket) {
             this.loading = true;
             try {
                 // Log Action
                 await this.logTicketAction(ticket.id, 'Disponibilizou Retirada', 'Cliente notificado para retirada');

                 // REFACTORED: Native Fetch
                 await this.supabaseFetch(`tickets?id=eq.${ticket.id}`, 'PATCH', {
                    pickup_available: true,
                    pickup_available_at: new Date().toISOString()
                });
                await this.fetchTickets();
             } catch(e) {
                 this.notify("Erro: " + e.message, "error");
             } finally {
                this.loading = false;
             }
        },
        async confirmPickup(ticket = this.selectedTicket) {
            await this.updateStatus(ticket, 'Finalizado', {}, { action: 'Finalizou Entrega', details: 'Entregue ao cliente' });
        },

        async requestPriority(ticket) {
            this.loading = true;
            try {
                // Log Action
                await this.logTicketAction(ticket.id, 'Solicitou Prioridade', 'Cliente/Atendente solicitou urgência máxima');

                // Update
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
            // Filter tickets based on toggle
            let source = this.tickets.filter(t => t.status !== 'Finalizado' && t.deadline);

            // Determine Effective Filter
            let effectiveFilter = this.selectedTechFilter;
            if (!this.hasRole('admin') && this.hasRole('tecnico')) {
                effectiveFilter = this.user.id;
            }

            // Apply Technician Filter (Strict)
            if (effectiveFilter !== 'all' && effectiveFilter) {
                source = source.filter(t => t.technician_id === effectiveFilter);
            }

            if (!this.showAllCalendarTickets) {
                // Only assigned to me (conceptually - for now we use "created_by" or just all if we assume single shop,
                // but user asked "atribuidos ao tecnico".
                // Since we don't have a distinct "assigned_to" field in the schema yet,
                // I will filter by the Technical Statuses that would appear on "Minha Bancada" OR if created by me?
                // The user said "todos atribuidos ao tecnico".
                // In the current system, "Minha Bancada" shows ALL tickets in Analise/Reparo.
                // So I will stick to that logic + maybe "Testes"?
                // Let's filter by statuses relevant to a technician.
                const techStatuses = ['Analise Tecnica', 'Andamento Reparo'];
                source = source.filter(t => techStatuses.includes(t.status));
            }
            return source;
        },

        getWeekDays() {
            const curr = new Date();
            const first = curr.getDate() - curr.getDay(); // First day is the day of the month - the day of the week
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

            // Pad empty days at start
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

        // --- UTILS ---
        getStatusLabel(status) {
            return this.STATUS_LABELS[status] || status;
        },

        getTechnicians() {
            return this.employees.filter(e => e.roles && e.roles.includes('tecnico'));
        },

        initTechFilter() {
            // Debugging
            console.log("Initializing Tech Filter. User:", this.user);

            // Prioritize setting filter to self if user is a technician (even if admin)
            // This ensures they see their own bench first.
            if (this.hasRole('tecnico') && this.user && this.user.id) {
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
                // REFACTORED: Native Fetch for RPC
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

        async deleteEmployee(id) {
            if (!confirm('Confirma?')) return;
            try {
                // REFACTORED: Native Fetch
                await this.supabaseFetch(`employees?id=eq.${id}`, 'DELETE');
                this.notify('Excluído.');
                this.fetchEmployees();
            } catch(e) {
                this.notify('Erro ao excluir', 'error');
            }
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
