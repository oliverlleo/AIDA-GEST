const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const main = fs.readFileSync(path.join(root, 'js', 'main.js'), 'utf8');
const featureConfig = fs.readFileSync(path.join(root, 'js', 'modules', 'feature-config.js'), 'utf8');
const customerService = fs.readFileSync(path.join(root, 'js', 'modules', 'customer-service.js'), 'utf8');
const ticketActions = fs.readFileSync(path.join(root, 'js', 'modules', 'ticket-actions.js'), 'utf8');

test('customer registry is enabled by default and restricted in the navigation', () => {
    assert.match(featureConfig, /DEFAULT_MODULES[\s\S]*customers:\s*true/);
    assert.match(main, /modules:\s*\{[\s\S]*customers:\s*true/);
    assert.match(html, /view = 'customers'/);
    assert.match(html, /isModuleEnabled\('customers'\)/);
    assert.match(html, /hasRole\('admin'\) \|\| hasRole\('atendente'\)/);
});

test('disabled registry keeps the legacy free-name ticket path', () => {
    assert.match(html, /x-model="ticketForm\.client_name"/);
    assert.match(html, /x-show="isModuleEnabled\('customers'\)"[\s\S]*openCustomerForm\('ticket'\)/);
    assert.match(ticketActions, /customer_id:\s*deps\.isModuleEnabled\('customers'\)[\s\S]*:\s*null/);
    assert.match(ticketActions, /client_name:\s*deps\.state\.ticketForm\.client_name/);
});

test('customer queries are bounded, paginated and do not preload all tickets', () => {
    assert.match(customerService, /PAGE_SIZE = 20/);
    assert.match(customerService, /LOOKUP_LIMIT = 8/);
    assert.match(customerService, /p_cursor:/);
    assert.match(customerService, /p_include_total:/);
    assert.match(customerService, /mergeUnique/);
    assert.match(main, /currentView === 'customers'[\s\S]*fetchCustomerPage\(true\)/);
    assert.doesNotMatch(customerService, /tickets\?select=\*/);
});

test('ticket detail and sharing reuse existing secure flows', () => {
    assert.match(html, /customerManagement\.tickets[\s\S]*viewTicketDetails\(ticket\)/);
    assert.match(html, /copyTrackingLink\(ticket\)/);
    assert.match(main, /async copyTrackingLink\(ticketOverride = null\)/);
    assert.match(main, /ensureCompleteTicket\(ticket\)/);
});

test('customer form requires only the name on the frontend', () => {
    assert.match(main, /if \(!name\)[\s\S]*customerFormErrors = \{ name: true \}/);
    assert.match(html, /Somente o nome é obrigatório/);
    assert.doesNotMatch(html, /Telefone \/ WhatsApp <span class="text-red-500">\*/);
    assert.doesNotMatch(html, /E-mail <span class="text-red-500">\*/);
});

test('ticket creation resolves an existing customer before saving the OS', () => {
    assert.match(main, /if \(this\.isModuleEnabled\('customers'\) && !this\.ticketForm\.customer_id\)/);
    assert.match(main, /exactMatches\.length === 1[\s\S]*this\.selectTicketCustomer\(exactMatches\[0\]\)/);
    assert.match(main, /exactMatches\.length > 1[\s\S]*Selecione o cadastro correto/i);
});
