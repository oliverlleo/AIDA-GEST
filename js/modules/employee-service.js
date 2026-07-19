// Employee Service
// Responsável pelas rotinas de gestão e listagem de funcionários
// Parte da infraestrutura de módulos

window.AIDAEmployeeService = {
    SAFE_EMPLOYEE_FIELDS: 'id,workspace_id,name,username,roles,created_at,deleted_at,must_change_password',

    getPasswordPolicyError(password) {
        if (typeof password !== 'string' || password.length < 8) {
            return 'A senha deve ter pelo menos 8 caracteres.';
        }

        const byteLength = typeof TextEncoder !== 'undefined'
            ? new TextEncoder().encode(password).length
            : unescape(encodeURIComponent(password)).length;

        if (byteLength > 72) return 'A senha deve ter no máximo 72 bytes.';
        if (!/[A-Za-zÀ-ÖØ-öø-ÿ]/.test(password) || !/[0-9]/.test(password)) {
            return 'A senha deve incluir pelo menos uma letra e um número.';
        }
        return '';
    },

    getTemporaryPasswordPolicyError(password) {
        if (typeof password !== 'string' || password.trim().length < 6) {
            return 'A senha temporária deve ter pelo menos 6 caracteres.';
        }

        const byteLength = typeof TextEncoder !== 'undefined'
            ? new TextEncoder().encode(password).length
            : unescape(encodeURIComponent(password)).length;

        if (byteLength > 72) return 'A senha temporária deve ter no máximo 72 bytes.';
        return '';
    },

    isAdmin(state) {
        return Boolean(state.session) || (state.user?.roles || []).includes('admin');
    },

    async fetchEmployees(deps) {
        const { state, supabaseFetch } = deps;
        if (!state.user?.workspace_id) return;
        try {
            // A leitura direta usa somente as colunas liberadas pela etapa 1;
            // o password_hash continua sem SELECT e a RLS limita a empresa.
            // Assim atendentes tambem recebem a lista necessaria para atribuir
            // o tecnico e criar agendamentos de analise ou reparo.
            const data = await supabaseFetch(`employees?select=${this.SAFE_EMPLOYEE_FIELDS}&workspace_id=eq.${state.user.workspace_id}&deleted_at=is.null&order=created_at.desc`);
            if (!data) return;

            let securityByEmployee = new Map();
            if (this.isAdmin(state)) {
                try {
                    const security = await supabaseFetch('rpc/get_employee_security_status', 'POST', {
                        p_workspace_id: state.user.workspace_id
                    });
                    securityByEmployee = new Map((security || []).map(item => [item.employee_id, item]));
                } catch (securityError) {
                    // A lista da equipe continua útil mesmo se o resumo de segurança falhar.
                    console.warn('Employee security status unavailable:', securityError);
                }
            }

            state.employees = data.map(employee => ({
                ...employee,
                failed_attempts: 0,
                lock_until: null,
                reset_required: false,
                manual_blocked: false,
                manual_blocked_at: null,
                manual_block_reason: null,
                active_sessions: 0,
                last_seen_at: null,
                ...(securityByEmployee.get(employee.id) || {})
            }));
        } catch (e) {
             console.error("Fetch Employees Error:", e);
        }
    },

    async createEmployee(deps) {
        const { state, supabaseFetch, notify, setLoading, fetchEmployees, closeModal } = deps;
        if (!state.user?.workspace_id) return notify('Erro workspace', 'error');
        if (!state.employeeForm.name || !state.employeeForm.username || !state.employeeForm.password) return notify('Preencha campos', 'error');
        const passwordError = this.getTemporaryPasswordPolicyError(state.employeeForm.password);
        if (passwordError) return notify(passwordError, 'error');

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
        if (state.employeeForm.password) {
            const passwordError = this.getTemporaryPasswordPolicyError(state.employeeForm.password);
            if (passwordError) return notify(passwordError, 'error');
        }

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
        const passwordError = this.getTemporaryPasswordPolicyError(newPassword);
        if (passwordError) return notify(passwordError, 'error');

        setLoading(true);
        try {
            await supabaseFetch('rpc/reset_employee_password', 'POST', {
                p_employee_id: employeeId,
                p_new_password: newPassword
            });
            notify("Senha resetada! O funcionário deverá trocar no próximo login.");
            closeModal('resetPassword');
            closeModal('editEmployee');
            if (deps.fetchEmployees) await deps.fetchEmployees();
        } catch (e) {
            notify("Erro ao resetar: " + e.message, "error");
        } finally {
            setLoading(false);
        }
    },

    async changeOwnPassword(deps) {
        const { state, supabaseFetch, notify, setLoading, processEmployeeLoginResponse, closeModal } = deps;
        const { oldPassword, newPassword, confirmPassword } = state.changePasswordForm;
        if (!oldPassword || !newPassword || !confirmPassword) return notify("Preencha todos os campos.", "error");
        if (newPassword !== confirmPassword) return notify("Nova senha não confere.", "error");
        const passwordError = this.getPasswordPolicyError(newPassword);
        if (passwordError) return notify(passwordError, 'error');

        setLoading(true);
        try {
            const token = state.employeeSession ? state.employeeSession.token : null;
            if (!token) throw new Error("Sessão inválida.");

            // 1. Altera a senha
            await supabaseFetch('rpc/employee_change_password', 'POST', {
                p_token: token,
                p_old_password: oldPassword,
                p_new_password: newPassword
            });

            // 2. Re-autentica forçadamente com a nova senha para obter um NOVO TOKEN do servidor,
            // garantindo que não caia no erro de "Workspace não identificado ou token inválido".
            const username = state.user.username || state.employeeSession.username || state.loginForm.username;
            const company_code = state.companyCode || state.loginForm.company_code;

            const reauthData = await supabaseFetch('rpc/employee_login', 'POST', {
                p_company_code: company_code,
                p_username: username,
                p_password: newPassword
            });

            if (reauthData && reauthData.length > 0) {
                // Remove modals before jumping into the response processor
                closeModal('forceChangePassword');

                // 3. O Helper processará o novo login e invocará o Bootstrap centralmente.
                deps.isReauth = true;
                await processEmployeeLoginResponse(reauthData[0], company_code, deps);
            } else {
                throw new Error("Falha na reautenticação após a troca de senha.");
            }

        } catch (e) {
            notify("Erro ao alterar senha: " + e.message, "error");
        } finally {
            setLoading(false);
        }
    },

    async setEmployeeAccountBlocked(employee, blocked, deps) {
        const { state, supabaseFetch, notify, setLoading, fetchEmployees, closeModal } = deps;
        if (!this.isAdmin(state)) return notify('Somente administradores podem alterar o bloqueio.', 'error');
        if (!employee?.id) return;

        const action = blocked ? 'bloquear' : 'desbloquear';
        if (!confirm(`Deseja ${action} o acesso de ${employee.name}?`)) return;

        let reason = null;
        if (blocked) {
            reason = prompt('Motivo do bloqueio (opcional):', '');
            if (reason === null) return;
        }

        setLoading(true);
        try {
            await supabaseFetch('rpc/set_employee_account_blocked', 'POST', {
                p_employee_id: employee.id,
                p_blocked: blocked,
                p_reason: reason || null
            });
            notify(blocked ? 'Acesso bloqueado e sessões encerradas.' : 'Acesso desbloqueado.');
            if (closeModal) closeModal('editEmployee');
            await fetchEmployees();
        } catch (e) {
            notify(`Erro ao ${action}: ${e.message}`, 'error');
        } finally {
            setLoading(false);
        }
    },

    async revokeEmployeeSessions(employee, deps) {
        const { state, supabaseFetch, notify, setLoading, fetchEmployees } = deps;
        if (!this.isAdmin(state)) return notify('Somente administradores podem encerrar sessões.', 'error');
        if (!employee?.id) return;
        if (!confirm(`Encerrar todas as sessões ativas de ${employee.name}?`)) return;

        setLoading(true);
        try {
            const result = await supabaseFetch('rpc/revoke_employee_sessions', 'POST', {
                p_employee_id: employee.id
            });
            const count = Number(Array.isArray(result) ? result[0] : result) || 0;
            notify(count === 1 ? '1 sessão encerrada.' : `${count} sessões encerradas.`);
            await fetchEmployees();
        } catch (e) {
            notify('Erro ao encerrar sessões: ' + e.message, 'error');
        } finally {
            setLoading(false);
        }
    }
};
