
// Configuração do Supabase
const SUPABASE_URL = 'https://cpydazjwlmssbzzsurxu.supabase.co';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNweWRhemp3bG1zc2J6enN1cnh1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc4Mjg5MTUsImV4cCI6MjA4MzQwNDkxNX0.NM7cuB6mks74ZzfvMYhluIjnqBXVgtolHbN4huKmE-Q';

// Renomeando para evitar conflito com variável global 'supabase' do CDN
const supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);

function app() {
    return {
        // State
        loading: false,
        session: null, // Admin Auth Session
        employeeSession: null, // Custom Employee Session object
        user: null, // Unified user object
        workspaceName: '',
        companyCode: '', // New: Store company code
        registrationSuccess: false, // New: Show welcome screen
        newCompanyCode: '', // New: Store new code for display
        view: 'dashboard', // dashboard, employees, service_orders, stock, setup_required
        authMode: 'employee', // employee, admin_login, admin_register

        // Data
        employees: [],
        notifications: [],

        // Forms
        loginForm: { company_code: '', username: '', password: '' },
        adminForm: { email: '', password: '' },
        registerForm: { companyName: '', email: '', password: '' },
        employeeForm: { name: '', username: '', password: '', roles: [] },

        // Modals
        modals: { newEmployee: false },

        async init() {
            this.loading = true;

            // Check for Admin Session
            const { data: { session } } = await supabaseClient.auth.getSession();
            if (session) {
                this.session = session;
                await this.loadAdminData();
            } else {
                // Check for Employee Session (Stored in localStorage)
                const storedEmp = localStorage.getItem('techassist_employee');
                if (storedEmp) {
                    this.employeeSession = JSON.parse(storedEmp);
                    this.user = this.employeeSession;
                    this.workspaceName = await this.getWorkspaceName(this.employeeSession.workspace_id);
                    // Also fetch employees if logged in as employee (to populate team view)
                    this.fetchEmployees();
                }
            }

            // Listen for Auth Changes (Admin)
            supabaseClient.auth.onAuthStateChange(async (_event, session) => {
                this.session = session;
                if (session) {
                    await this.loadAdminData();
                } else if (!this.employeeSession) {
                    this.user = null;
                }
            });

            this.loading = false;
        },

        // --- AUTHENTICATION ---

        async loginAdmin() {
            this.loading = true;
            const { error } = await supabaseClient.auth.signInWithPassword({
                email: this.adminForm.email,
                password: this.adminForm.password,
            });
            this.loading = false;
            if (error) this.notify(error.message, 'error');
        },

        async registerAdmin() {
            this.loading = true;
            // 1. Sign Up
            const { data: authData, error: authError } = await supabaseClient.auth.signUp({
                email: this.registerForm.email,
                password: this.registerForm.password,
            });

            if (authError) {
                this.loading = false;
                return this.notify(authError.message, 'error');
            }

            // If user already exists, signUp returns user/session.
            // Proceed to create workspace.

            if (authData.user) {
                if (!authData.session) {
                    this.loading = false;
                    return this.notify('Cadastro realizado! Verifique seu e-mail para confirmar a conta antes de entrar.', 'success');
                }

                await this.completeCompanySetup();
            }
            this.loading = false;
        },

        async completeCompanySetup() {
             this.loading = true;
             const generatedCode = Math.floor(1000 + Math.random() * 9000).toString();

             // Call the new ATOMIC RPC to create workspace AND profile
             const { data: wsId, error: wsError } = await supabaseClient
                .rpc('create_owner_workspace_and_profile', {
                    p_name: this.registerForm.companyName || 'Minha Assistência', // Fallback if name lost
                    p_company_code: generatedCode
                });

            if (wsError) {
                console.error(wsError);
                this.notify('Erro ao criar empresa: ' + wsError.message, 'error');
            } else {
                this.newCompanyCode = generatedCode;
                this.registrationSuccess = true;
                this.notify('Conta criada com sucesso!', 'success');
            }
            this.loading = false;
        },

        async loginEmployee() {
            this.loading = true;
            const { data, error } = await supabaseClient
                .rpc('employee_login', {
                    p_company_code: this.loginForm.company_code,
                    p_username: this.loginForm.username,
                    p_password: this.loginForm.password
                });

            this.loading = false;

            if (error) {
                console.error(error);
                this.notify('Falha no login. Verifique as credenciais.', 'error');
            } else if (data && data.length > 0) {
                const emp = data[0]; // RPC returns an array
                this.employeeSession = emp;
                this.user = emp;
                localStorage.setItem('techassist_employee', JSON.stringify(emp));
                this.workspaceName = await this.getWorkspaceName(emp.workspace_id);
                this.notify('Bem-vindo, ' + emp.name, 'success');
                this.fetchEmployees(); // Load colleagues
            } else {
                 this.notify('Credenciais inválidas.', 'error');
            }
        },

        async logout() {
            this.loading = true;
            try {
                if (this.session) {
                    await supabaseClient.auth.signOut();
                }
            } catch (error) {
                console.error("Logout error (network might be unreachable):", error);
            } finally {
                // Force cleanup local state regardless of server response
                this.employeeSession = null;
                this.user = null;
                this.session = null;
                this.workspaceName = '';
                localStorage.removeItem('techassist_employee');

                // Clear Supabase specific keys if any remain
                // But generally reloading clears memory state, localStorage persists.
                // Supabase client uses localStorage for session persistence, signOut usually clears it.
                // We can manually clear supabase keys if needed, but let's trust reload.

                this.view = 'dashboard';
                this.loading = false;
                window.location.reload();
            }
        },

        // --- DATA LOADING ---

        async loadAdminData() {
            if (!this.session) return;
            const user = this.session.user;

            // Fetch Profile & Workspace
            let { data: profile, error } = await supabaseClient
                .from('profiles')
                .select('*, workspaces(name, company_code)')
                .eq('id', user.id)
                .single();

            // CRITICAL RECOVERY: If profile missing...
            if (error && error.code === 'PGRST116') {
                console.log("Profile missing. Attempting self-repair...");

                // Try finding ANY workspace owned by user
                const { data: wsData } = await supabaseClient
                    .from('workspaces')
                    .select('id, name, company_code')
                    .eq('owner_id', user.id)
                    .single();

                if (wsData) {
                    // Workspace exists, create missing profile
                    await supabaseClient.from('profiles').insert([{
                        id: user.id,
                        workspace_id: wsData.id,
                        role: 'admin'
                    }]);

                    // Retry fetching profile
                     const retry = await supabaseClient
                        .from('profiles')
                        .select('*, workspaces(name, company_code)')
                        .eq('id', user.id)
                        .single();

                     profile = retry.data;
                     error = retry.error;
                } else {
                    // FATAL: Auth exists, but NO Workspace and NO Profile.
                    // Redirect to "Setup Required" view.
                    console.error("ZOMBIE ACCOUNT DETECTED: No workspace, no profile.");
                    this.view = 'setup_required';
                    return;
                }
            }

            if (error) {
                console.error("Error loading admin profile:", error);
            }

            if (profile) {
                this.user = {
                    id: user.id,
                    email: user.email,
                    name: 'Administrador',
                    roles: ['admin'],
                    workspace_id: profile.workspace_id
                };
                this.workspaceName = profile.workspaces?.name;
                this.companyCode = profile.workspaces?.company_code; // Store for display

                // Load Employees
                this.fetchEmployees();
            }
        },

        async fetchEmployees() {
            if (!this.user?.workspace_id) return;

            let result;

            if (this.session) {
                // Admin: Standard Select (RLS works because auth.uid() is owner)
                result = await supabaseClient
                    .from('employees')
                    .select('*')
                    .eq('workspace_id', this.user.workspace_id)
                    .order('created_at', { ascending: false });
            } else {
                // Employee: Use Secure RPC (bypasses RLS) because they are not "auth users"
                result = await supabaseClient
                    .rpc('get_employees_for_workspace', {
                        p_workspace_id: this.user.workspace_id
                    });
            }

            const { data, error } = result;

            if (!error) {
                this.employees = data;
            } else {
                console.error("Error fetching employees:", error);
            }
        },

        async getWorkspaceName(id) {
            // Public read allowed? No.
            // But if employee login succeeded, we know the workspace ID.
            // We can't query workspace table directly if RLS blocks it for non-owners.
            // However, the RPC could return workspace name too.
            // For now, let's just try or skip.
            // Or better: update RPC to return workspace name.
            // As a fallback, we just don't show it or show ID.
            return 'Área de Trabalho';
        },

        // --- ACTIONS ---

        openModal(name) {
            this.employeeForm = { name: '', username: '', password: '', roles: [] };
            this.modals[name] = true;
        },

        async createEmployee() {
            // Debug check for workspace ID
            if (!this.user?.workspace_id) {
                console.error("Workspace ID missing in user object:", this.user);
                return this.notify('Erro: Identificador da empresa não carregado. Recarregue a página.', 'error');
            }

            if (!this.employeeForm.name || !this.employeeForm.username || !this.employeeForm.password) {
                return this.notify('Preencha todos os campos', 'error');
            }

            this.loading = true;

            const { error } = await supabaseClient.rpc('create_employee', {
                p_workspace_id: this.user.workspace_id,
                p_name: this.employeeForm.name,
                p_username: this.employeeForm.username,
                p_password: this.employeeForm.password,
                p_roles: this.employeeForm.roles
            });

            this.loading = false;

            if (error) {
                console.error(error);
                this.notify('Erro ao criar funcionário: ' + error.message, 'error');
            } else {
                this.notify('Funcionário criado!', 'success');
                this.modals.newEmployee = false;
                this.fetchEmployees();
            }
        },

        async deleteEmployee(id) {
            if (!confirm('Tem certeza?')) return;

            const { error } = await supabaseClient
                .from('employees')
                .delete()
                .eq('id', id);

            if (error) {
                this.notify('Erro ao excluir.', 'error');
            } else {
                this.notify('Funcionário removido.', 'success');
                this.fetchEmployees();
            }
        },

        // --- UTILS ---

        hasRole(role) {
            // Se for o dono da conta (admin logado por email), tem acesso total
            if (this.session && role === 'admin') return true;

            if (!this.user) return false;

            // Verificação segura de roles
            const roles = this.user.roles || [];
            if (roles.includes('admin')) return true;

            return roles.includes(role);
        },

        notify(message, type = 'success') {
            const id = Date.now();
            this.notifications.push({ id, message, type });
            setTimeout(() => {
                this.notifications = this.notifications.filter(n => n.id !== id);
            }, 3000);
        }
    }
}
