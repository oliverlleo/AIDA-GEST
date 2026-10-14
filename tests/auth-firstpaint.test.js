const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '../js/auth-firstpaint.js'), 'utf8');

function presentation(keys = [], blocked = false) {
    const attributes = new Map();
    const context = {
        URL, SUPABASE_CONFIG: { URL: 'https://project.supabase.co' },
        document: { documentElement: {
            setAttribute: (name, value) => attributes.set(name, value),
            removeAttribute: name => attributes.delete(name)
        } },
        localStorage: {
            get length() { if (blocked) throw new Error('Storage unavailable'); return keys.length; },
            key: index => keys[index],
            getItem() { throw new Error('Credentials must not be read'); }
        }
    };
    context.window = context;
    vm.runInNewContext(source, context);
    return { attributes, hint: context.AIDAAuthFirstPaint, context };
}

test('sem sessão do projeto, o login fica visível desde o primeiro paint', () => {
    const { attributes, hint } = presentation(['centralos_workspace:user', 'techassist_employee', 'sb-other-auth-token']);
    assert.equal(attributes.has('data-auth-pending'), false);
    assert.equal(hint.storageKey, 'sb-project-auth-token');
});
test('com sessão armazenada, o login aguarda o SDK sem ler credenciais nem conceder acesso', () => {
    const { attributes, hint, context } = presentation(['sb-project-auth-token']);
    assert.equal(attributes.get('data-auth-pending'), 'true');
    assert.equal(context.session, undefined);
    assert.equal(context.user, undefined);
    hint.release();
    assert.equal(attributes.has('data-auth-pending'), false);
});
test('storage bloqueado aguarda a verificação real e permite liberar a apresentação', () => {
    const { attributes, hint } = presentation([], true);
    assert.equal(attributes.has('data-auth-pending'), true);
    hint.release();
    assert.equal(attributes.has('data-auth-pending'), false);
});
