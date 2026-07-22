const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const main = fs.readFileSync(path.join(__dirname, '..', 'js', 'main.js'), 'utf8');

test('combobox de chamados declara o estado usado ao carregar mais itens', () => {
    const start = main.indexOf('ticketCombobox()');
    const end = main.indexOf('\n        defectCombobox()', start);
    const component = main.slice(start, end > start ? end : start + 8000);

    assert.notEqual(start, -1);
    assert.match(component, /loadingMore:\s*false/);
    assert.match(component, /if \(this\.loadingMore\) return/);
});
