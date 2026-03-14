// Employee Service
// Responsável pelas rotinas de gestão e listagem de funcionários
// Parte da infraestrutura de módulos

window.AIDAEmployeeService = {
    async fetchEmployees(deps) {
        const { state, supabaseFetch } = deps;
        if (!state.user?.workspace_id) return;
        try {
            let data;
            if (state.session) {
                 data = await supabaseFetch(`employees?select=*&workspace_id=eq.${state.user.workspace_id}&deleted_at=is.null&order=created_at.desc`);
            } else {
                 data = await supabaseFetch('rpc/get_employees_for_workspace', 'POST', { p_workspace_id: state.user.workspace_id });
            }
            if (data) state.employees = data;
        } catch (e) {
             console.error("Fetch Employees Error:", e);
        }
    },

    async createEmployee(deps) {
        const { state, supabaseFetch, notify, setLoading, fetchEmployees, closeModal } = deps;
        if (!state.user?.workspace_id) return notify('Erro workspace', 'error');
        if (!state.employeeForm.name || !state.employeeForm.username || !state.employeeForm.password) return notify('Preencha campos', 'error');

        setLoading(true);
        try {
            await supabaseFetch('rpc/create_employee', 'POST', {
                p_workspace_id: state.user.workspace_id,
                p_name: state.employeeForm.name,
                p_username: state.employeeForm.username,
                p_password: state.employeeForm.password,
                p_roles: state.employeeForm.roles
            });

            notify('Criado!');
            closeModal('newEmployee');
            await fetchEmployees();
        } catch(e) {
            console.error(e);
            notify('Erro: ' + e.message, 'error');
        } finally {
            setLoading(false);
        }
    },

    async updateEmployee(deps) {
        const { state, supabaseFetch, notify, setLoading, fetchEmployees, closeModal } = deps;
        if (!state.employeeForm.id) return;
        if (!state.employeeForm.name || !state.employeeForm.username) return notify('Preencha campos obrigatórios', 'error');

        setLoading(true);
        try {
            await supabaseFetch('rpc/update_employee', 'POST', {
                p_id: state.employeeForm.id,
                p_name: state.employeeForm.name,
                p_username: state.employeeForm.username,
                p_password: state.employeeForm.password,
                p_roles: state.employeeForm.roles
            });

            notify('Atualizado!');
            closeModal('editEmployee');
            await fetchEmployees();
        } catch(e) {
            console.error(e);
            notify('Erro: ' + e.message, 'error');
        } finally {
            setLoading(false);
        }
    },

    async deleteEmployee(id, deps) {
        const { supabaseFetch, notify, fetchEmployees } = deps;
        if (!confirm('Tem certeza que deseja mover este funcionário para a Lixeira?')) return;
        try {
            await supabaseFetch(`employees?id=eq.${id}`, 'PATCH', {
                deleted_at: new Date().toISOString()
            });
            notify('Funcionário movido para a Lixeira.');
            await fetchEmployees();
        } catch(e) {
            notify('Erro ao excluir: ' + e.message, 'error');
        }
    },

    async resetEmployeePassword(deps) {
        const { state, supabaseFetch, notify, setLoading, closeModal } = deps;
        const { employeeId, newPassword, confirmPassword } = state.resetPasswordForm;
        if (!newPassword || !confirmPassword) return notify("Preencha as senhas.", "error");
        if (newPassword !== confirmPassword) return notify("Senhas não conferem.", "error");

        setLoading(true);
        try {
            await supabaseFetch('rpc/reset_employee_password', 'POST', {
                p_employee_id: employeeId,
                p_new_password: newPassword
            });
            notify("Senha resetada! O funcionário deverá trocar no próximo login.");
            closeModal('resetPassword');
            closeModal('editEmployee');
        } catch (e) {
            notify("Erro ao resetar: " + e.message, "error");
        } finally {
            setLoading(false);
        }
    },

    async changeOwnPassword(deps) {
        const { state, supabaseFetch, notify, setLoading, validateSessionToken, bootstrapAuthenticatedApp, closeModal } = deps;
        const { oldPassword, newPassword, confirmPassword } = state.changePasswordForm;
        if (!oldPassword || !newPassword || !confirmPassword) return notify("Preencha todos os campos.", "error");
        if (newPassword !== confirmPassword) return notify("Nova senha não confere.", "error");

        setLoading(true);
        try {
            const token = state.employeeSession ? state.employeeSession.token : null;
            if (!token) throw new Error("Sessão inválida.");

            await supabaseFetch('rpc/employee_change_password', 'POST', {
                p_token: token,
                p_old_password: oldPassword,
                p_new_password: newPassword
            });

            notify("Senha alterada com sucesso!");

            // Revalida a sessão com o servidor para garantir workspace_id e roles exatas
            const freshSession = await validateSessionToken({ state, supabaseFetch });
            if (freshSession) {
                state.employeeSession.workspace_id = freshSession.workspace_id;
                state.employeeSession.employee_id = freshSession.employee_id;
                state.employeeSession.roles = freshSession.roles || [];
                if (!state.employeeSession.id) state.employeeSession.id = freshSession.employee_id;
            }

            // Atualiza sessão local e garante que o usuário esteja coerente antes do bootstrap
            state.employeeSession.must_change_password = false;
            state.user = state.employeeSession;
            if (freshSession && freshSession.workspace_name) state.workspaceName = freshSession.workspace_name;

            localStorage.setItem('techassist_employee', JSON.stringify(state.employeeSession));

            // Corrige o fluxo de view no primeiro acesso lendo a sessão real recém configurada
            const roles = state.user.roles || [];
            const isTech = roles.includes('tecnico');
            const isTester = roles.includes('tester');
            const isAdminOrAttendant = roles.includes('admin') || roles.includes('atendente');

            if (isTester && !isAdminOrAttendant) {
                state.view = 'tester_bench';
            } else if (isTech && !isAdminOrAttendant) {
                state.view = 'tech_orders';
            } else {
                state.view = 'dashboard';
            }

            // Limpa modais e libera interface principal
            state.mustChangePassword = false;
            closeModal('forceChangePassword');

            // Usa a via central unificada de carregamento (sem reconstruir na mão)
            await bootstrapAuthenticatedApp({ reason: 'password_changed' });

        } catch (e) {
            notify("Erro ao alterar senha: " + e.message, "error");
        } finally {
            setLoading(false);
        }
    }
};
