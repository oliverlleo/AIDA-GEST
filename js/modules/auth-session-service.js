// Auth & Session Service
// Responsável pelas rotinas de autenticação e validação de sessão
// Parte da infraestrutura de módulos

window.AIDAAuthSessionService = {
    async loginAdmin(deps) {
        const { state, supabaseClient, notify, setLoading } = deps;
        setLoading(true);
        try {
            const { error } = await supabaseClient.auth.signInWithPassword({
                email: state.adminForm.email,
                password: state.adminForm.password,
            });
            if (error) notify(error.message, 'error');
        } finally {
            setLoading(false);
        }
    },

    async registerAdmin(deps) {
        const { state, supabaseClient, notify, setLoading } = deps;
        setLoading(true);
        try {
            const { data: authData, error: authError } = await supabaseClient.auth.signUp({
                email: state.registerForm.email,
                password: state.registerForm.password,
            });
            if (authError) return notify(authError.message, 'error');
            if (authData.user && !authData.session) return notify('Verifique seu e-mail.', 'success');
        } finally {
            setLoading(false);
        }
    },

    async completeCompanySetup(deps) {
        const { state, supabaseFetch, notify, setLoading } = deps;
        setLoading(true);
        try {
            if (!state.registerForm.companyName) return notify('Digite o nome da empresa.', 'error');
            const generatedCode = Math.floor(1000 + Math.random() * 9000).toString();

            await supabaseFetch('rpc/create_owner_workspace_and_profile', 'POST', {
                   p_name: state.registerForm.companyName,
                   p_company_code: generatedCode
            });

            state.newCompanyCode = generatedCode;
            state.registrationSuccess = true;
            notify('Conta criada! Anote o código.', 'success');
        } catch (err) {
            console.error(err);
            notify('Erro: ' + err.message, 'error');
        } finally {
            setLoading(false);
        }
    },

    async loginEmployee(deps) {
        const { state, supabaseFetch, notify, setLoading, hasRole, bootstrapAuthenticatedApp } = deps;
        setLoading(true);
        try {
            const data = await supabaseFetch('rpc/employee_login', 'POST', {
                    p_company_code: state.loginForm.company_code,
                    p_username: state.loginForm.username,
                    p_password: state.loginForm.password
            });

            if (data && data.length > 0) {
                const result = data[0];
                const emp = result.employee_json;
                emp.token = result.token;
                emp.must_change_password = result.must_change_password;

                if (emp.employee_id && !emp.id) {
                    emp.id = emp.employee_id;
                }

                state.employeeSession = emp;
                state.user = emp;
                state.workspaceName = emp.workspace_name;
                state.companyCode = state.loginForm.company_code;
                if (emp.whatsapp_number) state.whatsappNumber = emp.whatsapp_number;

                if (emp.tracker_config) {
                    state.trackerConfig = {
                        ...state.trackerConfig,
                        ...emp.tracker_config,
                        colors: {
                            ...state.trackerConfig.colors,
                            ...(emp.tracker_config.colors || {})
                        },
                        required_ticket_fields: {
                            ...state.trackerConfig.required_ticket_fields,
                            ...(emp.tracker_config.required_ticket_fields || {})
                        }
                    };
                }

                // Ajusta a view corretamente antes de qualquer return/early exit
                if (hasRole('tester') && !hasRole('admin') && !hasRole('atendente')) {
                    state.view = 'tester_bench';
                } else if (hasRole('tecnico') && !hasRole('admin') && !hasRole('atendente')) {
                    state.view = 'tech_orders';
                }

                if (emp.must_change_password) {
                    state.mustChangePassword = true;
                    state.modals.forceChangePassword = true;
                    localStorage.setItem('techassist_employee', JSON.stringify(emp));
                    return;
                }

                localStorage.setItem('techassist_employee', JSON.stringify(emp));
                notify('Bem-vindo, ' + emp.name, 'success');

                await bootstrapAuthenticatedApp({ reason: 'login_employee' });
            } else {
                 notify('Credenciais inválidas.', 'error');
            }
        } catch(err) {
             console.error(err);
             notify('Falha no login: ' + err.message, 'error');
        } finally {
            setLoading(false);
        }
    },

    async logout(deps) {
        const { state, supabaseFetch, supabaseClient, setLoading, _applyContext } = deps;
        setLoading(true);

        if (state.employeeSession && state.employeeSession.token) {
            try {
                await supabaseFetch('rpc/employee_logout', 'POST', { p_token: state.employeeSession.token });
            } catch (e) { console.warn("Logout RPC warning:", e); }
        }

        try { if (state.session) await supabaseClient.auth.signOut(); } catch (e) {}

        state.employeeSession = null;
        state.user = null;
        state.session = null;
        state.notificationsList = [];
        localStorage.removeItem('techassist_employee');

        _applyContext(window.AIDATicketContext.clearContext());

        state.view = 'dashboard';
        setLoading(false);
        window.location.reload();
    },

    async validateSessionToken(deps) {
        const { state, supabaseFetch } = deps;
        try {
            const sessionData = await supabaseFetch('rpc/validate_employee_session', 'POST', { p_token: state.employeeSession.token });
            if (!sessionData || sessionData.length === 0 || !sessionData[0].valid) {
                return null;
            }
            return sessionData[0];
        } catch (err) {
            console.warn("Session validation failed:", err);
            return null;
        }
    },

    async loadAdminData(deps) {
        const { state, supabaseFetch, bootstrapAuthenticatedApp } = deps;
        if (!state.session) return;
        const user = state.session.user;
        const key = user.id;

        if (state.loadedToken === key) {
            console.log('[Auth] Skipping loadAdminData - already loaded for', key);
            return;
        }

        console.log('[Auth] loadAdminData start...', key);

        try {
            const profileData = await supabaseFetch(`profiles?select=*,workspaces(name,company_code,whatsapp_number,tracker_config)&id=eq.${user.id}`);
            let profile = profileData && profileData.length > 0 ? profileData[0] : null;

            if (!profile) {
                const wsData = await supabaseFetch(`workspaces?select=id,name,company_code,whatsapp_number&owner_id=eq.${user.id}`);
                const workspace = wsData && wsData.length > 0 ? wsData[0] : null;

                if (workspace) {
                    await supabaseFetch('profiles', 'POST', { id: user.id, workspace_id: workspace.id, role: 'admin' });
                    const newProfileData = await supabaseFetch(`profiles?select=*,workspaces(name,company_code,whatsapp_number,tracker_config)&id=eq.${user.id}`);
                    profile = newProfileData[0];
                } else {
                    state.view = 'setup_required';
                    return;
                }
            }

            if (profile) {
                state.user = { id: user.id, email: user.email, name: 'Administrador', roles: ['admin'], workspace_id: profile.workspace_id };
                state.workspaceName = profile.workspaces?.name;
                state.companyCode = profile.workspaces?.company_code;
                state.whatsappNumber = profile.workspaces?.whatsapp_number || '';

                if (profile.workspaces?.tracker_config) {
                    state.trackerConfig = {
                        ...state.trackerConfig,
                        ...profile.workspaces.tracker_config,
                        colors: {
                            ...state.trackerConfig.colors,
                            ...(profile.workspaces.tracker_config.colors || {})
                        },
                        required_ticket_fields: {
                            ...state.trackerConfig.required_ticket_fields,
                            ...(profile.workspaces.tracker_config.required_ticket_fields || {})
                        }
                    };
                }

                await bootstrapAuthenticatedApp({ reason: 'load_admin' });

                state.loadedToken = key;
            }
        } catch (err) {
            console.error("Load Admin Error:", err);
        }
    }
};
