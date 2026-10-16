const test = require('node:test');
const assert = require('node:assert/strict');
global.window = global;
require('../js/modules/notes-service.js');

test('checklist envia somente o item e seu estado desejado, nunca array antiga', async () => {
    const note = { id: 'note', checklist_data: [{ item: 'A', ok: false }, { item: 'B', ok: false }] };
    let sent;
    await global.AIDANotesService.toggleNoteCheckStatus(note, 0, {
        supabaseFetch: async (endpoint, method, payload) => {
            sent = { endpoint, method, payload };
            return { id: 'note', checklist_data: [{ item: 'A', ok: true }, { item: 'B', ok: true }] };
        }
    });
    assert.equal(sent.endpoint, 'rpc/set_note_check_status');
    assert.deepEqual(sent.payload, { p_note_id: 'note', p_item_index: 0, p_item_text: 'A', p_expected_ok: false, p_new_ok: true });
    assert.deepEqual(note.checklist_data.map(item => item.ok), [true, true]);
});

test('duplo clique enquanto grava não inverte o item de novo; falha preserva o estado anterior', async () => {
    const note = { id: 'pending-note', checklist_data: [{ item: 'A', ok: false }] };
    let rejectRequest, calls = 0, notices = 0;
    const deps = { supabaseFetch: () => { calls++; return new Promise((_resolve, reject) => { rejectRequest = reject; }); }, notify: () => { notices++; } };
    const first = global.AIDANotesService.toggleNoteCheckStatus(note, 0, deps);
    await global.AIDANotesService.toggleNoteCheckStatus(note, 0, deps);
    assert.equal(calls, 1);
    assert.equal(note.checklist_data[0].ok, true);
    rejectRequest(new Error('offline'));
    await first;
    assert.equal(note.checklist_data[0].ok, false);
    assert.equal(notices, 1);
});
