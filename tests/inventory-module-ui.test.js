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
const managementServiceSource = fs.readFileSync(path.join(root, 'js', 'modules', 'inventory-management-service.js'), 'utf8');
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
    assert.match(html, /setInventoryItemLocation\(location, \$event\.target\.checked\)/);
    assert.match(html, /Endereço principal \(opcional\)/);
    assert.match(catalogServiceSource, /rpc\/set_inventory_item_locations/);
    assert.match(storageServiceSource, /inventory_images\/\$\{encodedPath\}/);
    assert.match(storageServiceSource, /getInventoryImageUrl/);
    assert.match(storageServiceSource, /deleteInventoryImage/);
    assert.doesNotMatch(storageServiceSource, /inventory\/\/\_/);
    assert.match(main, /this\.inventory\.itemForm\.id = itemId/);
});

test('item location picker is searchable, grouped and renders a bounded result window', () => {
    assert.match(html, /Buscar estante, gaveta ou endereço/);
    assert.match(html, /Todos os organizadores/);
    assert.match(html, /visibleInventoryItemLocations\(\)/);
    assert.match(html, /Mostrar mais/);
    assert.match(main, /visibleLimit:\s*24/);
    assert.match(main, /inventoryItemLocationResults\(\)[\s\S]*groupId[\s\S]*toLocaleLowerCase\('pt-BR'\)/);
    assert.match(main, /visibleInventoryItemLocations\(\)[\s\S]*slice\(0,\s*this\.inventory\.itemLocationPicker\.visibleLimit\)/);
});

test('reserved stock opens a paginated OS list only when requested', async () => {
    assert.match(html, /@click="openInventoryReservations\(item\)"/);
    assert.match(html, /OS com peça reservada/);
    assert.match(html, /Carregar mais OS/);
    assert.match(main, /openInventoryReservations\(item\)/);
    assert.match(main, /openTicketFromInventoryReservation\(ticket\)/);

    const context = { window: {} };
    vm.createContext(context);
    vm.runInContext(managementServiceSource, context);
    let call;
    const response = { items: [], total: 0, has_more: false, next_cursor: null };
    const deps = {
        supabaseFetch: async (endpoint, method, payload) => {
            call = { endpoint, method, payload };
            return response;
        }
    };
    const result = await context.window.AIDAInventoryManagementService.loadItemReservations(
        deps,
        'item-id',
        { reserved_at: '2026-07-30T12:00:00Z', ticket_id: 'ticket-id' }
    );
    assert.deepEqual(result, response);
    assert.equal(call.endpoint, 'rpc/get_inventory_item_reservations_page');
    assert.equal(call.payload.p_limit, 20);
    assert.equal(call.payload.p_item_id, 'item-id');
    assert.equal(Object.hasOwn(call.payload, 'p_workspace_id'), false);
    assert.equal(Object.hasOwn(call.payload, 'workspace_id'), false);
});

test('inventory header can start the existing audited entry flow with a paginated item picker', () => {
    assert.match(html, /@click="openInventoryAdjustModal\(\)"[^>]*>[\s\S]*?Registrar entrada/);
    assert.match(html, /Buscar por nome, código, marca ou localização/);
    assert.match(html, /Carregar mais itens/);
    assert.match(html, /selectInventoryAdjustmentItem\(item\)/);
    assert.match(main, /openInventoryAdjustModal\(item = null\)/);
    assert.match(main, /loadInventoryAdjustmentItems\(reset = false\)[\s\S]*fetchItems/);
    assert.match(main, /stockFilter:\s*'all'/);
    assert.match(main, /limit:\s*15/);
    assert.match(main, /selectInventoryAdjustmentItem\(item\)[\s\S]*item_id:\s*item\.id/);
    assert.match(main, /submitInventoryAdjustment\(\)[\s\S]*registerEntry\(deps, this\.inventory\.adjustForm\)/);
    assert.doesNotMatch(main, /loadInventoryAdjustmentItems[\s\S]{0,800}p_workspace_id/);
});

test('location manager uses organizer groups and internal addresses', () => {
    assert.match(html, /Nova estante, armário ou área/);
    assert.match(html, /Endereços internos/);
    assert.match(html, /Adicionar vários endereços/);
    assert.match(html, /inventoryLocationGroup/);
    assert.match(main, /saveInventoryLocationGroup/);
    assert.match(main, /saveInventoryLocationBatch/);
    assert.match(main, /manageInventoryLocation\(location, action\)/);
});

test('purchase receipt can go directly to its OS without a stock address', () => {
    assert.match(html, /Direto para a OS/);
    assert.match(html, /Não exige localização/);
    assert.match(html, /Guardar no estoque/);
    assert.match(html, /item\.destination === 'stock'/);
    assert.match(html, /item\.destination === 'direct_ticket'/);
    assert.match(main, /direct_quantity_available/);
});

test('receiving new ticket parts opens repair scheduling and supports consecutive tickets', () => {
    assert.match(main, /inventoryRepairScheduleQueue:\s*\[\]/);
    assert.match(main, /ticket\.status === 'Andamento Reparo'/);
    assert.match(main, /ticket\.parts_status === 'Recebido'/);
    assert.match(main, /openSchedulePanel\([\s\S]*'inventoryReceiptRepair'/);
    assert.match(main, /afterSave === 'inventoryReceiptRepair'/);
    assert.match(main, /Reparo agendado e chamado enviado para reparo/);
});

test('received parts awaiting schedule never return to the purchase action', () => {
    assert.match(main, /ticketAwaitsRepairSchedule\(ticket\)/);
    assert.match(main, /return 'Agendar Reparo'/);
    assert.match(main, /ticket\?\.parts_status === 'Recebido'/);
    assert.match(main, /ticketAwaitsRepairSchedule\(ticket\)[\s\S]*openSchedulePanel\([\s\S]*'inventoryReceiptRepair'/);
    assert.match(html, /ticketPartsActionLabel\(ticket\) === 'Agendar Reparo'/);
});
