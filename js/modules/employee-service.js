// Staff administration changes workspace access, never another person's Auth account.
window.AIDAEmployeeService = {
    SAFE_EMPLOYEE_FIELDS: 'id,workspace_id,name,username,roles,created_at,deleted_at',
    isAdmin(state) { return (state.user?.roles || []).includes('admin'); },
    validRoles(roles) { return Array.isArray(roles) && roles.length > 0 && roles.every(role => ['admin', 'atendente', 'tecnico', 'tester'].includes(role)); },
    async fetchEmployees(deps) {
        const { state, supabaseFetch } = deps;
        if (!state.user?.workspace_id) return;
        try {
            const data = this.isAdmin(state)
                ? await supabaseFetch('rpc/list_workspace_staff', 'POST', { p_workspace_id: state.user.workspace_id })
                : await supabaseFetch(`employees?select=${this.SAFE_EMPLOYEE_FIELDS}&workspace_id=eq.${state.user.workspace_id}&legacy_auth_disabled=eq.false&deleted_at=is.null&order=created_at.desc`);
            // Removed staff belongs in the recycle bin, not in technician/appointment pickers.
            state.employees = (data || []).filter(employee => employee.access_status !== 'removed')
                .map(employee => ({ ...employee, manual_blocked: employee.access_status === 'blocked' }));
            if (this.isAdmin(state)) await this.fetchWorkspaceInvitations(deps);
        } catch (_) { if (deps.notify) deps.notify('Não foi possível carregar a equipe.', 'error'); }
    },
    async fetchWorkspaceInvitations(deps) {
        const { state, supabaseFetch } = deps;
        if (!this.isAdmin(state)) return;
        state.workspaceInvitations = await supabaseFetch('rpc/get_my_workspace_invitations', 'POST', { p_workspace_id: state.user.workspace_id }) || [];
    },
    async sendInvitation(invitationId, deps) {
        const { state, SUPABASE_URL, SUPABASE_KEY } = deps;
        if (!this.isAdmin(state) || !state.session?.access_token) throw new Error('Acesso administrativo necessário.');
        try {
            const response = await fetch(`${SUPABASE_URL}/functions/v1/send-workspace-invitation`, {
                method: 'POST', headers: {
                    apikey: SUPABASE_KEY, Authorization: `Bearer ${state.session.access_token}`,
                    'Content-Type': 'application/json', 'x-workspace-id': state.user.workspace_id
                }, body: JSON.stringify({ invitation_id: invitationId, workspace_id: state.user.workspace_id })
            });
            const result = await response.json().catch(() => ({}));
            if (response.status === 429) {
                const error = window.AIDAApiClient.createApiError(response, result);
                return { sent: false, status: 'rate_limited', retryAfter: error.retryAfter };
            }
            return response.ok && result.sent === true ? { sent: true, status: result.status }
                : { sent: false, status: result.error_code === 'email_configuration_missing' ? 'pending_configuration' : 'failed' };
        } catch (_) { return { sent: false, status: 'failed' }; }
    },
    notifyDelivery(result, notify) {
        if (result.status === 'rate_limited') {
            notify(`Convite salvo. Aguarde ${result.retryAfter || 60} segundos para reenviar o e-mail; você já pode copiar o link para o funcionário.`);
            return;
        }
        if (result.status === 'pending_configuration') {
            notify('Convite salvo. Copie o link para enviar ao funcionário; o e-mail será ativado quando o SMTP estiver configurado.');
            return;
        }
        notify(result.sent
            ? 'Convite salvo. O envio do e-mail foi aceito pelo provedor.'
            : 'Convite salvo. O e-mail não pôde ser enviado; copie o link ou tente reenviar.', result.sent ? 'success' : 'error');
    },
    async createEmployee(deps) {
        const { state, supabaseFetch, notify, setLoading, fetchEmployees, closeModal } = deps;
        if (!this.isAdmin(state)) return notify('Somente administradores podem convidar.', 'error');
        const form = state.employeeForm, email = String(form.email || '').trim().toLowerCase(), name = String(form.name || '').trim();
        if (!name || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || !this.validRoles(form.roles)) return notify('Informe nome, e-mail válido e pelo menos uma permissão.', 'error');
        setLoading(true);
        try {
            const id = await supabaseFetch('rpc/create_workspace_invitation', 'POST', {
                p_workspace_id: state.user.workspace_id, p_name: name, p_email: email, p_roles: form.roles, p_employee_id: form.id || null
            });
            this.notifyDelivery(await this.sendInvitation(id, deps), notify);
            closeModal('newEmployee'); await fetchEmployees();
        } catch (error) { notify('Não foi possível criar o convite: ' + error.message, 'error'); }
        finally { setLoading(false); }
    },
    async updateEmployee(deps) {
        const { state, supabaseFetch, notify, setLoading, fetchEmployees, closeModal } = deps;
        if (!this.isAdmin(state)) return notify('Somente administradores podem alterar permissões.', 'error');
        const form = state.employeeForm;
        if (!form.id || !String(form.name || '').trim() || !this.validRoles(form.roles)) return notify('Informe nome e permissões.', 'error');
        setLoading(true);
        try {
            await supabaseFetch('rpc/update_employee_access', 'POST', { p_employee_id: form.id, p_name: form.name.trim(), p_roles: form.roles });
            notify('Permissões atualizadas nesta empresa.'); closeModal('editEmployee'); await fetchEmployees();
        } catch (error) { notify('Não foi possível atualizar: ' + error.message, 'error'); }
        finally { setLoading(false); }
    },
    async deleteEmployee(id, deps) {
        const { state, supabaseFetch, notify, fetchEmployees } = deps;
        if (!this.isAdmin(state)) return;
        if (!confirm('Remover o acesso deste funcionário nesta empresa e movê-lo para a Lixeira?')) return;
        try {
            await supabaseFetch('rpc/set_employee_removed', 'POST', { p_employee_id: id, p_removed: true });
            notify('Acesso removido nesta empresa.'); await fetchEmployees();
        } catch (error) { notify('Não foi possível remover: ' + error.message, 'error'); }
    },
    async setEmployeeAccountBlocked(employee, blocked, deps) {
        const { state, supabaseFetch, notify, setLoading, fetchEmployees, closeModal } = deps;
        if (!this.isAdmin(state) || !employee?.id) return;
        if (!confirm(`${blocked ? 'Bloquear' : 'Liberar'} o acesso de ${employee.name} somente nesta empresa?`)) return;
        const reason = blocked ? prompt('Motivo do bloqueio (opcional):', '') : null;
        if (blocked && reason === null) return;
        setLoading(true);
        try {
            await supabaseFetch('rpc/set_employee_account_blocked', 'POST', { p_employee_id: employee.id, p_blocked: blocked, p_reason: reason || null });
            notify(blocked ? 'Acesso bloqueado nesta empresa.' : 'Acesso liberado nesta empresa.');
            if (closeModal) closeModal('editEmployee'); await fetchEmployees();
        } catch (error) { notify('Não foi possível alterar o acesso: ' + error.message, 'error'); }
        finally { setLoading(false); }
    },
    async revokeEmployeeSessions(employee, deps) {
        const { state, supabaseFetch, notify, setLoading, fetchEmployees } = deps;
        if (!this.isAdmin(state) || !employee?.id) return;
        if (!confirm(`Exigir que ${employee.name} entre novamente para acessar esta empresa?`)) return;
        setLoading(true);
        try {
            await supabaseFetch('rpc/revoke_employee_sessions', 'POST', { p_employee_id: employee.id });
            notify('Uma nova entrada será exigida nesta empresa.'); await fetchEmployees();
        } catch (error) { notify('Não foi possível exigir uma nova entrada: ' + error.message, 'error'); }
        finally { setLoading(false); }
    },
    async reissueInvitation(invitation, deps) {
        const { state, supabaseFetch, notify, setLoading, fetchEmployees } = deps;
        if (!this.isAdmin(state)) return;
        setLoading(true);
        try {
            const id = await supabaseFetch('rpc/reissue_workspace_invitation', 'POST', { p_invitation_id: invitation.invitation_id });
            this.notifyDelivery(await this.sendInvitation(id, deps), notify); await fetchEmployees();
        } catch (error) { notify('Não foi possível renovar o convite: ' + error.message, 'error'); }
        finally { setLoading(false); }
    },
    async resendInvitation(invitation, deps) {
        if (!this.isAdmin(deps.state)) return;
        deps.setLoading(true);
        try { this.notifyDelivery(await this.sendInvitation(invitation.invitation_id, deps), deps.notify); await deps.fetchEmployees(); }
        finally { deps.setLoading(false); }
    },
    async cancelInvitation(invitation, deps) {
        if (!this.isAdmin(deps.state) || !confirm('Cancelar este convite?')) return;
        deps.setLoading(true);
        try {
            await deps.supabaseFetch('rpc/cancel_workspace_invitation', 'POST', { p_invitation_id: invitation.invitation_id });
            deps.notify('Convite cancelado.'); await deps.fetchEmployees();
        } catch (error) { deps.notify('Não foi possível cancelar: ' + error.message, 'error'); }
        finally { deps.setLoading(false); }
    },
    async copyInvitationLink(invitation, deps) {
        const id = invitation.invitation_id;
        if (!window.AIDAAuthSessionService.UUID_PATTERN.test(id || '')) return;
        const url = window.AIDAAuthSessionService.getAppUrl(); url.searchParams.set('invitation', id);
        deps.state.lastInvitationLink = url.href;
        try { await navigator.clipboard.writeText(url.href); deps.notify('Link copiado. Só o e-mail convidado pode aceitá-lo.'); }
        catch (_) { deps.notify('Copie o link exibido na lista de convites.'); }
    }
};
