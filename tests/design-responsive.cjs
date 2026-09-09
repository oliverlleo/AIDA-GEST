/* Run with Playwright installed: node tests/design-responsive.cjs
 * Uses an isolated local server and synthetic UI state. No production requests,
 * credentials, mutations, or authentication bypass are shipped with the app.
 */
const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const out = process.env.AIDA_DESIGN_RESULTS || path.join(root, 'test-results', 'design');
fs.mkdirSync(out, { recursive: true });
const fixture = `
const originalAppForVisualTest = app;
app = function () {
    const state = originalAppForVisualTest();
    state.init = function () {
        this.STATUS_INDEX_MAP = this.STATUS_COLUMNS.reduce((a,s,i) => (a[s]=i,a), {});
        this.session = { user: { id: 'visual-admin' } };
        this.user = { id: 'visual-admin', name: 'Marina Costa', roles: ['admin'], workspace_id: 'visual-workspace' };
        this.workspaceName = 'Assistência Central'; this.companyCode = 'DEMO';
        this.loading = false; this.error = null;
        this.trackerConfig.modules.inventory = true;
        this.trackerConfig.customization.modules = true;
        this.trackerConfig.test_flow = 'tester';
        Object.assign(this.homeStatusCounts,{open:12,analysis:8,approval:3,pickup:5});
        Object.assign(this.homeOperationalCounts,{today:9,today_tomorrow:14,next_7_days:23,overdue:2,no_deadline:3,all:28});
        this.selectedTicket = {
            id: 'visual-ticket', os_number: 2048, device_model: 'iPhone 15 Pro', client_name: 'Ana Oliveira',
            status: 'Aberto', priority: 'Normal', created_at: new Date().toISOString(),
            photos: [], notes: [], checklist: [], parts: [], technician_id: null,
            defect: 'Tela com falha no toque', description: 'Verificar o funcionamento do aparelho.',
            warranty_claim: false, warranty_status: null
        };
        this.employees = [{id:'visual-tech',name:'Rafael Santos',username:'rafael',roles:['tecnico'],active:true}];
        this.deviceModels = [{id:'visual-model',name:'iPhone 15 Pro'}];
        this.inventory.items = [{id:'visual-part',name:'Display OLED para iPhone 15 Pro',sku:'DSP-15P',brand:'Premium',physical_quantity:12,reserved_quantity:3,available_quantity:9,minimum_quantity:5,ideal_quantity:15,track_stock:true,average_cost:425,last_cost:440,primary_location:'Estante A / Caixa 02'}];
        Object.assign(this.inventory.dashboard,{active_items:28,estimated_stock_value:18450,low_stock_items:4,out_of_stock_items:2,open_purchases:3,pending_ticket_parts:5});
        const customer={id:'visual-customer',name:'Ana Oliveira',phone:'11999990000',email:'ana@example.invalid',created_at:new Date().toISOString()};
        Object.assign(this.customerManagement,{items:[customer],selected:customer,total:1,hasMore:false,tickets:[this.selectedTicket],ticketsTotal:1,ticketsHasMore:false});
    };
    return state;
};`;
const failures = [];
const observations = [];
const errors = [];
const server = http.createServer((req,res) => {
    const url = new URL(req.url, 'http://localhost');
    let filename = path.resolve(root, '.' + (url.pathname === '/' ? '/index.html' : url.pathname));
    if (!filename.startsWith(root + path.sep)) { res.writeHead(403).end(); return; }
    if (url.pathname === '/js/supabase-config.js') {
        res.setHeader('Content-Type','application/javascript');
        res.end('window.SUPABASE_CONFIG={URL:"https://aida-ui-fixture.invalid",KEY:"visual-test-only"}'); return;
    }
    if (!fs.existsSync(filename)) { res.writeHead(404).end(); return; }
    const types={'.html':'text/html','.js':'application/javascript','.css':'text/css','.png':'image/png'};
    res.setHeader('Content-Type',types[path.extname(filename)] || 'text/plain');
    if (url.pathname === '/js/main.js') res.end(fs.readFileSync(filename,'utf8') + fixture);
    else res.end(fs.readFileSync(filename));
});
const setState = (page, values) => page.evaluate(values => Object.assign(Alpine.$data(document.body),values),values);
const settle = page => page.evaluate(() => new Promise(resolve => Alpine.nextTick(() => requestAnimationFrame(() => requestAnimationFrame(resolve)))));
async function audit(page, label) {
    await settle(page);
    const result = await page.evaluate(() => {
        const visible = el => !!(el.getClientRects().length && getComputedStyle(el).visibility !== 'hidden');
        const vw=innerWidth, vh=innerHeight;
        const outside=[];
        for(const el of document.querySelectorAll('button,input,select,textarea,h1,h2,.aida-dialog')) {
            if(!visible(el) || el.matches('[type=hidden],.sr-only')) continue;
            const r=el.getBoundingClientRect();
            if(r.width===0 || r.height===0) continue;
            // A control may deliberately live in a horizontally scrollable tab bar,
            // table, or Kanban lane; it must remain reachable by scrolling that region.
            let scrollParent=false;
            for(let p=el.parentElement;p && p!==document.body;p=p.parentElement) {
                const s=getComputedStyle(p);
                if(['auto','scroll'].includes(s.overflowX) && p.scrollWidth>p.clientWidth+1) {scrollParent=true;break;}
            }
            if((r.left < -2 || r.right > vw+2) && !scrollParent) outside.push({tag:el.tagName,text:(el.innerText||el.getAttribute('placeholder')||el.className).slice(0,90),left:Math.round(r.left),right:Math.round(r.right)});
        }
        const overlays=[...document.querySelectorAll('.aida-overlay')].filter(visible);
        return {width:vw,height:vh,documentOverflow:document.documentElement.scrollWidth>vw+1,outside,overlays:overlays.length};
    });
    observations.push({label,...result});
    if(result.documentOverflow || result.outside.length) failures.push({label,...result});
}
(async()=>{
    await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
    const url=`http://127.0.0.1:${server.address().port}`;
    const browser=await chromium.launch({headless:true, ...(process.env.AIDA_BROWSER_PATH ? {executablePath:process.env.AIDA_BROWSER_PATH} : {})});
    try {
        const context=await browser.newContext({viewport:{width:1440,height:1000},reducedMotion:'reduce'});
        await context.route('https://aida-ui-fixture.invalid/**',route=>route.fulfill({status:200,contentType:'application/json',body:'[]'}));
        const page=await context.newPage();
        page.on('pageerror',e=>errors.push(e.message));
        await page.goto(url);
        await page.waitForFunction(()=>window.Alpine && document.body._x_dataStack);
        await page.evaluate(()=>document.fonts.ready);
        const views=await page.locator('.aida-sidebar a').evaluateAll(els=>els.map(el=>({label:el.textContent.trim(),view:el.getAttribute('@click.prevent')?.match(/view = '([^']+)'/)?.[1]})).filter(el=>el.view));
        const modals=await page.evaluate(()=>Object.keys(Alpine.$data(document.body).modals));
        for(const width of [1440,768,390,320]) {
            await page.setViewportSize({width,height:width>=768?1000:844});
            for(const {view,label} of views) {
                await setState(page,{view});
                await audit(page,`${width}:view:${view}`);
                if(['dashboard','inventory','customers','management_settings'].includes(view) && [1440,390].includes(width))
                    await page.screenshot({path:path.join(out,`${width}-${view}.png`)});
            }
            await setState(page,{view:'dashboard'});
            for(const modal of modals) {
                await page.evaluate(modal=>{const s=Alpine.$data(document.body);Object.keys(s.modals).forEach(k=>s.modals[k]=false);s.modals[modal]=true;},modal);
                await audit(page,`${width}:modal:${modal}`);
                if(['ticket','viewTicket','inventoryItem','inventoryPurchase'].includes(modal) && [1440,390].includes(width))
                    await page.screenshot({path:path.join(out,`${width}-modal-${modal}.png`)});
            }
            await page.evaluate(()=>{const s=Alpine.$data(document.body);Object.keys(s.modals).forEach(k=>s.modals[k]=false);s.showNotesSidebar=true;});
            await audit(page,`${width}:notes`);
            await setState(page,{showNotesSidebar:false,schedulePanelOpen:true});
            await audit(page,`${width}:schedule-drawer`);
            await setState(page,{schedulePanelOpen:false});
            await setState(page,{showShareModal:true});
            await audit(page,`${width}:share`);
            await setState(page,{showShareModal:false});
            await page.evaluate(()=>Alpine.$data(document.body).overviewQueueModal.open=true);
            await audit(page,`${width}:overview-queue`);
            await page.evaluate(()=>Alpine.$data(document.body).overviewQueueModal.open=false);
        }
        // Real DOM actions: navigation, tab changes, form entry and cancellation.
        fs.writeFileSync(path.join(out,'report.json'),JSON.stringify({observations,failures,errors:[...new Set(errors)]},null,2));
        await page.setViewportSize({width:390,height:844});
        await page.locator('.aida-sidebar a').filter({hasText:'Chamados'}).click();
        assert.equal(await page.evaluate(()=>Alpine.$data(document.body).view),'kanban');
        await page.evaluate(()=>Alpine.$data(document.body).modals.ticket=true);
        const ticket=page.locator('.aida-dialog').filter({has:page.locator('[x-model="ticketForm.client_name"]')});
        await ticket.locator('[x-model="ticketForm.client_name"]').fill('Cliente de teste');
        await ticket.getByRole('button',{name:'Cancelar',exact:true}).click();
        assert.equal(await page.evaluate(()=>Alpine.$data(document.body).modals.ticket),false);
        await page.evaluate(()=>Alpine.$data(document.body).modals.viewTicket=true);
        await page.locator('.aida-tabs button').filter({hasText:'Notas'}).click();
        await page.locator('.aida-tabs button').filter({hasText:'Detalhes'}).click();
        await page.locator('.aida-tabs button').filter({hasText:'Agendamentos'}).click();
        await audit(page,'390:ticket-appointments-tab');
        await page.evaluate(()=>Alpine.$data(document.body).modals.viewTicket=false);
        await setState(page,{view:'cadastros'});
        for(const tab of ['models','defects','checklists','suppliers']) {
            await page.evaluate(tab=>Alpine.$data(document.body).catalogManagement.activeTab=tab,tab);
            await audit(page,`390:catalog:${tab}`);
        }
        // A nested customer dialog must be above the ticket form and preserve its values.
        await page.evaluate(()=>{const s=Alpine.$data(document.body);s.modals.ticket=true;s.modals.customerForm=true;});
        await audit(page,'390:nested-customer-form');
        await page.locator('[x-show="modals.customerForm && isModuleEnabled(\'customers\')"]').getByRole('button',{name:'Cancelar',exact:true}).click();
        assert.equal(await page.evaluate(()=>Alpine.$data(document.body).ticketForm.client_name),'Cliente de teste');
        await page.evaluate(()=>Alpine.$data(document.body).modals.ticket=false);
        await page.setViewportSize({width:844,height:390});
        await page.evaluate(()=>Alpine.$data(document.body).modals.inventoryReturn=true);
        await audit(page,'844x390:short-dialog');
        await page.locator('[x-show="modals.inventoryReturn"]').getByRole('button',{name:'Cancelar',exact:true}).click();
        await page.setViewportSize({width:390,height:844});
        for(const role of ['atendente','tecnico','tester']) {
            await page.evaluate(role=>{const s=Alpine.$data(document.body);s.session=null;s.employeeSession={id:'visual-employee'};s.user.roles=[role];s.view=role==='tester'?'tester_bench':role==='tecnico'?'tech_orders':'dashboard';},role);
            await audit(page,`390:role:${role}`);
            assert.equal(await page.locator('.aida-sidebar a').filter({hasText:'Configuração'}).count(),0);
        }
        await page.evaluate(()=>{const s=Alpine.$data(document.body);s.modals.viewTicket=false;s.session=null;s.employeeSession=null;});
        await audit(page,'390:login');
        await page.getByRole('button',{name:'Admin',exact:true}).click();
        await page.getByRole('textbox',{name:'E-mail Admin'}).fill('visual@example.invalid');
        await audit(page,'390:login-admin');
        for (const width of [1440,768,390,320]) {
            await page.setViewportSize({width,height:width>=768?1000:844});
            await audit(page,`${width}:login-composition`);
            await page.screenshot({path:path.join(out,`${width}-login.png`)});
        }
        await page.setViewportSize({width:390,height:844});
        await page.getByRole('textbox',{name:'E-mail Admin'}).focus();
        await page.keyboard.press('Tab');
        assert.equal(await page.evaluate(()=>getComputedStyle(document.activeElement).outlineStyle),'solid');
        // The public page must keep inline customer colors and render without x-cloak flashes.
        await page.goto(url+'/acompanhar.html');
        await page.waitForFunction(()=>document.body._x_dataStack);
        await page.evaluate(()=>{const s=Alpine.$data(document.body);s.loading=false;s.error=null;s.ticket={os_number:2048,device_model:'iPhone 15 Pro',status:'Aberto',created_at:new Date().toISOString(),client_name:'Ana Oliveira'};});
        await audit(page,'390:tracker');
        await page.screenshot({path:path.join(out,'390-tracker.png')});
        fs.writeFileSync(path.join(out,'report.json'),JSON.stringify({observations,failures,errors:[...new Set(errors)]},null,2));
        console.log(JSON.stringify({screens:observations.length,failures,errors:[...new Set(errors)]},null,2));
        if(failures.length || errors.length) process.exitCode=1;
        await context.close();
    } finally { await browser.close();server.close(); }
})().catch(error=>{console.error(error);server.close();process.exitCode=1;});
