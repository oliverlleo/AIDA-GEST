const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.join(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const main = fs.readFileSync(path.join(root, 'js', 'main.js'), 'utf8');
const featureConfig = fs.readFileSync(path.join(root, 'js', 'modules', 'feature-config.js'), 'utf8');
const ticketActions = fs.readFileSync(path.join(root, 'js', 'modules', 'ticket-actions.js'), 'utf8');
const queryServiceSource = fs.readFileSync(path.join(root, 'js', 'modules', 'inventory-query-service.js'), 'utf8');
const catalogServiceSource = fs.readFileSync(path.join(root, 'js', 'modules', 'inventory-catalog-service.js'), 'utf8');
const storageServiceSource = fs.readFileSync(path.join(root, 'js', 'modules', 'storage-service.js'), 'utf8');

test('inventory defaults off and remains dependent on the existing parts flow', () => {
    assert.match(featureConfig, /DEFAULT_MODULES[\s\S]*inventory:\s*false/);
    assert.match(featureConfig, /workflow\.parts_control === false\) modules\.inventory = false/);
    assert.match(main, /inventory:\s*false/);
    assert.match(html, /modules\.inventory/);
    assert.match(html, /isInventoryEnabled\(\)/);
});

test('navigation and management page expose inventory only to admin and attendant', () => {
    assert.match(html, /view = 'inventory'/);
    assert.match(html, /hasRole\('atendente'\) && !hasRole\('admin'\) && isInventoryEnabled\(\)/);
    assert.match(html, /x-show="hasRole\('admin'\)"[\s\S]*Novo item/i);
    assert.match(html, /view === 'inventory'[\s\S]*hasRole\('admin'\) \|\| hasRole\('atendente'\)/);
    assert.doesNotMatch(html, /hasRole\('testador'\)[\s\S]{0,120}view = 'inventory'/);
});

test('inventory list is paginated, filtered in the database and details load on demand', () => {
    assert.match(main, /loadMoreInventory\(\)/);
    assert.match(main, /nextCursor/);
    assert.match(html, /Carregar mais itens/);
    assert.match(html, /x-model="inventory\.category"/);
    assert.match(html, /Com solicitação pendente/);
    assert.match(html, /Itens arquivados/);
    assert.match(main, /loadItemDetail/);
    assert.doesNotMatch(queryServiceSource, /inventory_movements\?select=\*/);
});

test('ticket flows use structured parts only when inventory is enabled and preserve legacy fields otherwise', () => {
    assert.match(ticketActions, /function inventoryEnabled\(deps\)/);
    assert.match(ticketActions, /requestTicketParts/);
    assert.match(ticketActions, /approve_ticket_with_inventory/);
    assert.match(ticketActions, /complete_repair_with_inventory/);
    assert.match(ticketActions, /!inventoryEnabled\(deps\)[\s\S]*parts_needed/i);
    assert.match(ticketActions, /supplier_purchases|parts_status/i);
});

test('part selector shows availability, location, compatibility and manual alternatives', () => {
    assert.match(html, /Compatível com este aparelho/);
    assert.match(html, /Alternativas — escolha manualmente/);
    assert.match(html, /item\.primary_location/);
    assert.match(html, /item\.available_quantity/);
    assert.match(html, /Quantidade usada/);
    assert.match(html, /Devolver ao estoque/);
});

test('creation selector calls the bounded model-aware RPC without sending a workspace', async () => {
    const context = { window: {} };
    vm.createContext(context);
    vm.runInContext(queryServiceSource, context);
    let call;
    const response = { items: [], has_more: false, next_cursor: null };
    const deps = {
        supabaseFetch: async (endpoint, method, payload) => {
            call = { endpoint, method, payload };
            return response;
        }
    };
    const result = await context.window.AIDAInventoryQueryService.fetchCreationCatalog(
        deps,
        'iPhone 13',
        { search: 'tela', limit: 20 }
    );
    assert.deepEqual(result, response);
    assert.equal(call.endpoint, 'rpc/get_inventory_creation_catalog_page');
    assert.equal(call.payload.p_device_model, 'iPhone 13');
    assert.equal(call.payload.p_search, 'tela');
    assert.equal(Object.hasOwn(call.payload, 'workspace_id'), false);
    assert.equal(Object.hasOwn(call.payload, 'p_workspace_id'), false);
});

test('item form supports private image files and multiple independent storage locations', () => {
    assert.match(html, /type="file"[^>]+accept="image\/jpeg,image\/png,image\/webp"/i);
    assert.match(html, /x-model="inventory\.itemForm\.location_ids"/);
    assert.match(html, /Endereço principal \(opcional\)/);
    assert.match(catalogServiceSource, /rpc\/set_inventory_item_locations/);
    assert.match(storageServiceSource, /inventory_images\/\$\{encodedPath\}/);
    assert.match(storageServiceSource, /getInventoryImageUrl/);
    assert.match(storageServiceSource, /deleteInventoryImage/);
    assert.doesNotMatch(storageServiceSource, /inventory\/\/\_/);
    assert.match(main, /this\.inventory\.itemForm\.id = itemId/);
});

test('location manager creates concrete addresses and manages old patterns safely', () => {
    assert.match(html, /Gerar várias posições/);
    assert.match(html, /Endereços cadastrados/);
    assert.match(html, /Padrões antigos/);
    assert.match(html, /manageInventoryLocationScheme/);
    assert.match(main, /generateInventoryLocations/);
    assert.match(main, /manageInventoryLocation\(location, action\)/);
    assert.match(main, /manageInventoryLocationScheme\(scheme, action\)/);
});