// Converts known scheduling conflicts into short messages without exposing
// database internals or raw SQL errors to the user.
window.AIDAScheduleErrorService = {
    getUserMessage(error, fallback = 'Não foi possível salvar o agendamento.') {
        const rawMessage = String(error?.message || error || '');
        const message = rawMessage.toLocaleLowerCase('pt-BR');

        if (message.includes('já existe um agendamento') ||
            message.includes('ticket_appointments_active_ticket_type_uidx')) {
            return 'Esta OS já possui um agendamento ativo para essa etapa.';
        }

        if (message.includes('capacidade máxima do slot')) {
            return 'Esse horário acabou de ser ocupado. Escolha outro horário disponível.';
        }

        if (message.includes('capacidade diária máxima')) {
            return 'O técnico atingiu o limite de agendamentos deste dia.';
        }

        if (message.includes('conflitante com um bloqueio')) {
            return 'Esse horário está bloqueado na agenda do técnico.';
        }

        if (message.includes('agendamento não encontrado') ||
            message.includes('inativo ou já cancelado')) {
            return 'Este agendamento foi alterado ou cancelado por outra pessoa. Atualize a agenda.';
        }

        if (message.includes('no passado') || message.includes('cruzar a meia-noite') ||
            message.includes('período do agendamento inválido') ||
            message.includes('término deve ser maior')) {
            return 'O período selecionado não é válido. Escolha outro horário.';
        }

        return fallback;
    }
};
