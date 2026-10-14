// Identity is authenticated by Supabase; permissions belong to the active membership.
window.AIDAAuthSessionService = {
    UUID_PATTERN: /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
    getAdminPasswordPolicyError(password) {
        if (typeof password !== 'string' || password.length < 8) return 'A senha deve ter pelo menos 8 caracteres.';
        const bytes = typeof TextEncoder !== 'undefined' ? new TextEncoder().encode(password).length : unescape(encodeURIComponent(password)).length;
        if (bytes > 72) return 'A senha deve ter no máximo 72 bytes.';
        if (!/[A-Za-zÀ-ÖØ-öø-ÿ]/.test(password) || !/[0-9]/.test(password)) return 'A senha deve incluir pelo menos uma letra e um número.';
        return '';
    },
    workspacePreferenceKey(userId) { return `centralos_workspace:${userId}`; },
    rememberWorkspace(userId, workspaceId) {
        try { localStorage.setItem(this.workspacePreferenceKey(userId), workspaceId); } catch (_) {}
    },
    getRememberedWorkspace(userId) {
        try { return localStorage.getItem(this.workspacePreferenceKey(userId)); } catch (_) { return null; }
    },
    getAppUrl() { return new URL('app.html', window.location.href); },
    getEmailRedirectUrl(state, purpose = 'confirm') {
        const url = this.getAppUrl();
        url.searchParams.set('auth', purpose);
        if (this.UUID_PATTERN.test(state.pendingInvitationId || '')) url.searchParams.set('invitation', state.pendingInvitationId);
        return url.href;
    },
    rememberPendingInvitation(state, url = new URL(window.location.href)) {
        let id = url.searchParams.get('invitation') || url.searchParams.get('invitation_id');
        try { if (!id) id = sessionStorage.getItem('centralos_pending_invitation'); } catch (_) {}
        if (!this.UUID_PATTERN.test(id || '')) return;
        state.pendingInvitationId = id;
        try { sessionStorage.setItem('centralos_pending_invitation', id); } catch (_) {}
    },
    async handleAuthCallback(deps) {
        const { state, supabaseClient, notify } = deps;
        const url = new URL(window.location.href);
        this.rememberPendingInvitation(state, url);
        const tokenHash = url.searchParams.get('token_hash'), type = url.searchParams.get('type');
        const code = url.searchParams.get('code'), purpose = url.searchParams.get('auth');
        const callbackError = url.searchParams.get('error') || url.searchParams.get('error_code');
        if (!tokenHash && !code && !callbackError) return;
        // Credentials are removed before asynchronous work, logging or navigation.
        ['token_hash', 'type', 'code', 'error', 'error_code', 'error_description', 'auth'].forEach(key => url.searchParams.delete(key));
        url.hash = '';
        window.history.replaceState({}, '', url.pathname + url.search);
        state.accessTransitioning = true;
        try {
            if (callbackError) throw new Error('Link indisponível.');
            if (tokenHash && !['email', 'signup', 'invite', 'recovery'].includes(type)) throw new Error('Tipo de confirmação inválido.');
            const result = tokenHash
                ? await supabaseClient.auth.verifyOtp({ token_hash: tokenHash, type })
                : await supabaseClient.auth.exchangeCodeForSession(code);
            if (result.error) throw result.error;
            state.session = result.data?.session || null;
            state.authUser = state.session?.user || result.data?.user || null;
            state.recoveryMode = type === 'recovery' || (Boolean(code) && purpose === 'recovery');
            state.authNotice = state.recoveryMode ? 'Defina sua nova senha.' : 'E-mail confirmado. Você já pode acessar sua conta.';
        } catch (_) {
            state.authError = 'O link expirou ou não pôde ser confirmado. Solicite um novo e-mail e tente novamente.';
            notify(state.authError, 'error');
        } finally { state.accessTransitioning = false; }
    },
    async login(deps) {
        const { state, supabaseClient, notify, setLoading } = deps;
        if (state.authBootstrapping || state.loading || state.accessTransitioning) return;
        state.authError = ''; state.accessTransitioning = true; setLoading(true);
        try {
            const { data, error } = await supabaseClient.auth.signInWithPassword({ email: String(state.authForm.email || '').trim(), password: state.authForm.password });
            if (error || !data?.session) throw error || new Error('Sessão indisponível.');
            const previousId = state.authUser?.id;
            state.session = data.session; state.authUser = data.session.user; state.authForm.password = '';
            if (previousId && previousId !== state.authUser.id) return window.location.replace(this.getAppUrl().href);
            if (state.reauthWorkspaceId) {
                this.rememberWorkspace(state.authUser.id, state.reauthWorkspaceId);
                return window.location.reload();
            }
            await this.loadAccessData(deps);
        } catch (_) {
            state.authError = 'Não foi possível entrar. Confira e-mail e senha e confirme seu e-mail.';
            notify(state.authError, 'error');
        } finally { state.accessTransitioning = false; setLoading(false); }
    },
    async register(deps) {
        const { state, supabaseClient, notify, setLoading } = deps;
        if (state.authBootstrapping || state.loading || state.accessTransitioning) return;
        const policyError = this.getAdminPasswordPolicyError(state.registerForm.password);
        if (policyError) return notify(policyError, 'error');
        state.authError = ''; state.accessTransitioning = true; setLoading(true);
        try {
            const { data, error } = await supabaseClient.auth.signUp({
                email: String(state.registerForm.email || '').trim(), password: state.registerForm.password,
                options: { emailRedirectTo: this.getEmailRedirectUrl(state) }
            });
            if (error) throw error;
            state.registerForm.password = ''; state.authForm.email = state.registerForm.email; state.authMode = 'login';
            if (data?.session) {
                state.session = data.session; state.authUser = data.session.user;
                await this.loadAccessData(deps);
            } else {
                state.authNotice = 'Confira seu e-mail para confirmar a conta. Depois entre para aceitar seus convites ou cadastrar sua empresa.';
                notify('Confira seu e-mail para confirmar sua conta.');
            }
        } catch (_) {
            state.authError = 'Não foi possível criar a conta. Confira os campos ou tente recuperar uma conta existente.';
            notify(state.authError, 'error');
        } finally { state.accessTransitioning = false; setLoading(false); }
    },
    async resendConfirmation(deps) {
        const { state, supabaseClient, notify, setLoading } = deps;
        if (state.authBootstrapping || state.loading || state.accessTransitioning) return;
        const email = String(state.authForm.email || state.registerForm.email || '').trim();
        if (!email) return notify('Informe seu e-mail.', 'error');
        setLoading(true);
        try {
            const { error } = await supabaseClient.auth.resend({ type: 'signup', email, options: { emailRedirectTo: this.getEmailRedirectUrl(state) } });
            if (error) throw error;
            state.authNotice = 'Se a conta precisar de confirmação, você receberá um novo e-mail.';
            notify(state.authNotice);
        } catch (_) { notify('Não foi possível reenviar agora. Aguarde um pouco e tente novamente.', 'error'); }
        finally { setLoading(false); }
    },
    async requestPasswordReset(deps) {
        const { state, supabaseClient, notify, setLoading } = deps;
        if (state.authBootstrapping || state.loading || state.accessTransitioning) return;
        const email = String(state.authForm.email || '').trim();
        if (!email) return notify('Informe seu e-mail para recuperar a senha.', 'error');
        setLoading(true);
        try {
            const { error } = await supabaseClient.auth.resetPasswordForEmail(email, { redirectTo: this.getEmailRedirectUrl(state, 'recovery') });
            if (error) throw error;
            state.authNotice = 'Se este e-mail estiver cadastrado, você receberá um link para definir uma nova senha.';
            notify(state.authNotice);
        } catch (_) { notify('Não foi possível enviar a recuperação agora. Tente novamente mais tarde.', 'error'); }
        finally { setLoading(false); }
    },
    async finishPasswordRecovery(deps) {
        const { state, supabaseClient, notify, setLoading } = deps;
        const { password, confirmPassword } = state.recoveryForm;
        if (!state.session || !state.recoveryMode) return notify('Abra um link válido de recuperação enviado para seu e-mail.', 'error');
        if (password !== confirmPassword) return notify('As senhas não conferem.', 'error');
        const policyError = this.getAdminPasswordPolicyError(password);
        if (policyError) return notify(policyError, 'error');
        setLoading(true);
        try {
            const { error } = await supabaseClient.auth.updateUser({ password });
            if (error) throw error;
            state.recoveryForm = { password: '', confirmPassword: '' }; state.recoveryMode = false;
            notify('Senha atualizada. Entre novamente com sua nova senha.');
            await this.logout(deps);
        } catch (_) { notify('Não foi possível atualizar sua senha. Solicite um novo link de recuperação.', 'error'); }
        finally { setLoading(false); }
    },
    async loadAccessData(deps) {
        const { state, supabaseFetch } = deps;
        if (!state.session?.user || state.recoveryMode || state.accessLoadInFlight) return;
        state.accessLoadInFlight = true; state.accessLoading = true; state.accessError = ''; state.authUser = state.session.user;
        try {
            const [workspaces, invitations] = await Promise.all([
                supabaseFetch('rpc/list_my_workspaces', 'POST', {}), supabaseFetch('rpc/list_my_pending_invitations', 'POST', {})
            ]);
            state.workspaces = Array.isArray(workspaces) ? workspaces : [];
            state.pendingInvitations = Array.isArray(invitations) ? invitations : [];
            const remembered = this.getRememberedWorkspace(state.authUser.id);
            const selected = state.workspaces.find(item => item.workspace_id === remembered) || (state.workspaces.length === 1 ? state.workspaces[0] : null);
            if (!selected || selected.requires_reauthentication) {
                state.user = null; state.employeeSession = null; state.view = 'access_hub'; state.accessHubOpen = true;
                state.reauthWorkspaceId = selected?.requires_reauthentication ? selected.workspace_id : null;
                if (state.reauthWorkspaceId) state.authForm.email = state.session.user.email;
                return;
            }
            const context = await supabaseFetch('rpc/get_my_access_context', 'POST', { p_workspace_id: selected.workspace_id });
            await this.applyAccessContext(Array.isArray(context) ? context[0] : context, deps);
            if (state.pendingInvitationId || (state.pendingInvitations.length && !state.accessWelcomeShown)) state.accessHubOpen = true;
            state.accessWelcomeShown = true;
        } catch (_) {
            state.accessError = 'Não foi possível verificar seu acesso. Tente novamente antes de abrir uma empresa.';
            if (!state.user?.workspace_id) { state.view = 'access_hub'; state.accessHubOpen = true; }
        } finally { state.accessLoadInFlight = false; state.accessLoading = false; }
    },
    async applyAccessContext(context, deps) {
        const { state, bootstrapAuthenticatedApp } = deps;
        if (!context?.workspace_id || context.auth_user_id !== state.session?.user?.id || !Array.isArray(context.roles)) throw new Error('Acesso inválido.');
        const employeeId = context.member_kind === 'employee' ? context.employee_id : null;
        if (context.member_kind === 'employee' && !employeeId) throw new Error('Funcionário não vinculado.');
        const key = `${context.auth_user_id}:${context.workspace_id}:${context.membership_id || ''}:${employeeId || 'owner'}:${context.roles.join(',')}`;
        if (state.loadedToken && state.loadedToken !== key) return window.location.reload();
        state.user = {
            id: employeeId || context.auth_user_id, auth_user_id: context.auth_user_id, employee_id: employeeId,
            membership_id: context.membership_id, member_kind: context.member_kind, workspace_id: context.workspace_id,
            name: context.name || 'Usuário', email: state.session.user.email, username: context.username || '', roles: context.roles
        };
        // Compatibility for operational modules: a membership, never a credential.
        state.employeeSession = employeeId ? { ...state.user } : null;
        state.workspaceName = context.workspace_name || ''; state.companyCode = ''; state.whatsappNumber = context.whatsapp_number || '';
        if (context.tracker_config) {
            const defaults = state.trackerConfig || {};
            state.trackerConfig = window.AIDAFeatureConfig.normalize({
                ...defaults,
                ...context.tracker_config,
                colors: { ...(defaults.colors || {}), ...(context.tracker_config.colors || {}) },
                required_ticket_fields: { ...(defaults.required_ticket_fields || {}), ...(context.tracker_config.required_ticket_fields || {}) }
            });
        }
        if (typeof state.normalizeFeatureConfig === 'function') state.normalizeFeatureConfig();
        this.rememberWorkspace(context.auth_user_id, context.workspace_id);
        state.reauthWorkspaceId = null; state.employeeSessionLastValidatedAt = Date.now();
        if (state.loadedToken === key) return;
        const roles = context.roles;
        state.view = roles.includes('admin') || roles.includes('atendente') ? 'dashboard' : roles.includes('tester') ? 'tester_bench' : 'tech_orders';
        state.loadedToken = key;
        await bootstrapAuthenticatedApp({ reason: 'workspace_access' });
    },
    async selectWorkspace(workspaceId, deps) {
        const { state, supabaseFetch, notify, setLoading } = deps;
        const workspace = state.workspaces.find(item => item.workspace_id === workspaceId);
        if (!workspace) return notify('Empresa indisponível para esta conta.', 'error');
        if (workspace.requires_reauthentication) {
            state.reauthWorkspaceId = workspaceId; state.authForm.email = state.session.user.email; state.authForm.password = ''; state.accessHubOpen = true;
            return;
        }
        if (state.user?.workspace_id === workspaceId) { state.accessHubOpen = false; return; }
        if (state.user?.workspace_id && !confirm('Trocar de empresa? Alterações que ainda não foram salvas serão descartadas.')) return;
        setLoading(true);
        try {
            await supabaseFetch('rpc/get_my_access_context', 'POST', { p_workspace_id: workspaceId });
            this.rememberWorkspace(state.session.user.id, workspaceId);
            window.AIDAStorageService?.clearLocalPhotoPreviews(); await deps.supabaseClient.removeAllChannels(); window.location.reload();
        } catch (_) { notify('O acesso a esta empresa não está mais disponível. Atualize a lista e tente novamente.', 'error'); }
        finally { setLoading(false); }
    },
    async acceptInvitation(invitationId, deps) {
        const { state, supabaseFetch, notify, setLoading } = deps;
        if (!this.UUID_PATTERN.test(invitationId || '')) return;
        setLoading(true);
        try {
            const workspaceId = await supabaseFetch('rpc/accept_workspace_invitation', 'POST', { p_invitation_id: invitationId });
            this.rememberWorkspace(state.session.user.id, workspaceId); state.pendingInvitationId = null;
            try { sessionStorage.removeItem('centralos_pending_invitation'); } catch (_) {}
            window.location.replace(this.getAppUrl().href);
        } catch (_) { notify('Convite indisponível. Entre com o e-mail convidado confirmado ou solicite um novo convite ao gestor.', 'error'); }
        finally { setLoading(false); }
    },
    async completeCompanySetup(deps) {
        const { state, supabaseFetch, notify, setLoading } = deps;
        const name = String(state.registerForm.companyName || '').trim();
        if (!name) return notify('Digite o nome da empresa.', 'error');
        if (!state.session) return;
        setLoading(true);
        try {
            const workspaceId = await supabaseFetch('rpc/create_company_workspace', 'POST', { p_name: name });
            this.rememberWorkspace(state.session.user.id, workspaceId); window.location.replace(this.getAppUrl().href);
        } catch (error) { notify('Não foi possível cadastrar a empresa: ' + error.message, 'error'); }
        finally { setLoading(false); }
    },
    async logout(deps) {
        const { state, supabaseClient, notify, setLoading } = deps;
        state.signingOut = true; setLoading(true);
        try {
            const { error } = await supabaseClient.auth.signOut({ scope: 'local' });
            if (error) throw error;
            await supabaseClient.removeAllChannels(); window.AIDAStorageService?.clearLocalPhotoPreviews();
            state.user = null; state.employeeSession = null; state.session = null;
            try { localStorage.removeItem('techassist_employee'); localStorage.removeItem('centralos_remember_login'); } catch (_) {}
            window.location.replace(this.getAppUrl().href);
        } catch (_) { state.signingOut = false; notify('Não foi possível sair. Tente novamente.', 'error'); }
        finally { setLoading(false); }
    }
};

(function loadCentralOSMobileLoginReference() {
    if (typeof document === 'undefined' || document.querySelector('script[data-centralos-mobile-login]')) return;
    const script = document.createElement('script');
    script.src = 'centralos-mobile-login-reference.js?v=4'; script.async = false; script.dataset.centralosMobileLogin = 'true';
    document.head.appendChild(script);
})();
