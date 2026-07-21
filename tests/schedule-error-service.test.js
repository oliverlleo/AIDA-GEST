const test = require('node:test');
const assert = require('node:assert/strict');

global.window = global;
require('../js/modules/schedule-error-service.js');

test('conflito simultaneo de horario recebe mensagem clara', () => {
    const message = global.AIDAScheduleErrorService.getUserMessage(
        new Error('Capacidade máxima do slot (1) atingida neste horário.')
    );

    assert.equal(
        message,
        'Esse horário acabou de ser ocupado. Escolha outro horário disponível.'
    );
});

test('agendamento duplicado da mesma etapa recebe mensagem clara', () => {
    const message = global.AIDAScheduleErrorService.getUserMessage(
        new Error('Já existe um agendamento de analysis ativo para este chamado.')
    );

    assert.equal(
        message,
        'Esta OS já possui um agendamento ativo para essa etapa.'
    );
});

test('erro desconhecido nao expoe detalhes do banco', () => {
    const message = global.AIDAScheduleErrorService.getUserMessage(
        new Error('relation private.secret does not exist'),
        'Falha ao salvar agendamento.'
    );

    assert.equal(message, 'Falha ao salvar agendamento.');
});
