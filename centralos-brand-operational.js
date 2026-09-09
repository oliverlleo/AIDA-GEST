(() => {
  'use strict';
  const mq = matchMedia('(max-width:767px)');
  const origins = new WeakMap();
  const cache = new Map();
  let activeKey = '', active = [], raf = 0;
  const norm = v => String(v || '').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/\s+/g,' ').trim();
  const state = () => { try { return Alpine?.$data?.(document.body) || null; } catch { return null; } };
  const view = () => state()?.view || '';
  const root = v => [...document.querySelectorAll('main [x-show]')].find(el => (el.getAttribute('x-show')||'').includes(`view === '${v}'`)) || null;
  const nav = () => [...document.querySelectorAll('nav[x-show]')].find(el => (el.getAttribute('x-show')||'').includes('session')) || null;
  const visible = el => {
    if (!el || !el.isConnected || el.hidden || el.hasAttribute('x-cloak') || el.style.display === 'none') return false;
    try { return getComputedStyle(el).display !== 'none'; } catch { return true; }
  };
  const logged = () => { const s=state(), n=nav(); return !!s && !!(s.session||s.employeeSession) && s.view!=='setup_required' && visible(n); };
  const click = el => el?.getAttribute('@click') || el?.getAttribute('x-on:click') || el?.getAttribute('@click.prevent') || '';
  const byClick = (parent, text) => [...(parent?.children||[])].find(ch => [...ch.querySelectorAll('button')].some(b=>click(b).includes(text))) || null;
  const dashboard = () => root('dashboard');
  const dashboardAction = () => {
    const saved=cache.get('dashboard'); if(saved?.isConnected) return saved;
    const h=dashboard()?.querySelector(':scope > header'), a=byClick(h,'openNewTicketModal()');
    if(a) cache.set('dashboard',a); return a;
  };
  const screenButton = (v,label,key) => {
    const saved=cache.get(key); if(saved?.isConnected) return saved;
    const r=root(v); if(!r) return null;
    const wanted=norm(label), b=[...r.querySelectorAll('button')].find(x=>norm(x.textContent)===wanted)||null;
    if(b) cache.set(key,b); return b;
  };
  const remember = node => { if(node&&!origins.has(node)) origins.set(node,{parent:node.parentNode,next:node.nextSibling,form:node.tagName==='BUTTON'?node.getAttribute('form'):null}); };
  const keepForm = b => {
    if(!b||b.tagName!=='BUTTON'||norm(b.getAttribute('type')||'submit')!=='submit') return;
    const f=b.closest('form'); if(!f) return;
    if(!f.id) f.id=`centralos-mobile-form-${Math.random().toString(36).slice(2,9)}`;
    b.setAttribute('form',f.id);
  };
  const restore = node => {
    const o=origins.get(node); if(!node||!o?.parent?.isConnected) return;
    o.next&&o.next.parentNode===o.parent ? o.parent.insertBefore(node,o.next) : o.parent.appendChild(node);
    node.classList.remove('centralos-mobile-action-button','centralos-mobile-action-primary','centralos-mobile-action-secondary','centralos-mobile-home-split');
    if(node.tagName==='BUTTON') o.form===null?node.removeAttribute('form'):node.setAttribute('form',o.form);
  };
  const zone = () => document.querySelector('.centralos-mobile-view-action-zone');
  const removeZone = () => zone()?.remove();
  const restoreActive = () => { active.forEach(restore); active=[]; activeKey=''; removeZone(); };
  const ensureZone = () => {
    if(!logged()) return null;
    let z=zone(); if(z) return z;
    const n=nav(); if(!visible(n)) return null;
    z=document.createElement('div'); z.className='centralos-mobile-view-action-zone'; z.setAttribute('aria-label','Ações da tela atual'); n.after(z); return z;
  };

  const prepHome = () => {
    const d=dashboard(), h=d?.querySelector(':scope > header'); if(!d||!h) return null;
    d.classList.add('centralos-dashboard');
    const a=dashboardAction(); if(!a) return null;
    const primary=[...a.children].find(x=>x.tagName==='BUTTON'&&click(x).includes('openNewTicketModal()'));
    if(!primary) return null;
    const more=[...a.children].find(x=>x.tagName==='BUTTON'&&click(x).includes('newTicketMenuOpen'));
    const menu=[...a.children].find(x=>(x.getAttribute?.('x-show')||'').includes('newTicketMenuOpen'));
    a.classList.add('centralos-dashboard-open-action'); primary.classList.add('centralos-dashboard-open-primary');
    more?.classList.add('centralos-dashboard-open-more'); menu?.classList.add('centralos-dashboard-open-menu');
    const f=byClick(h,'applyHomeOperationalWindow('); f?.classList.add('centralos-dashboard-filter-shell');
    return {a,h,f};
  };
  const desired = () => {
    if(!logged()) return null;
    const v=view();
    if(v==='dashboard'){const p=prepHome(); return p?{key:'dashboard',v,layout:'single',items:[[p.a,'home']]}:null;}
    if(v==='customers'){const b=screenButton(v,'Novo cliente','customers'); return b?{key:'customers',v,layout:'single',items:[[b,'primary']]}:null;}
    if(v==='management_settings'){const b=screenButton(v,'Salvar alterações','management'); return b?{key:'management',v,layout:'single',items:[[b,'primary']]}:null;}
    if(v==='tracker_settings'){
      const r=screenButton(v,'Redefinir','tracker-reset'), s=screenButton(v,'Salvar alterações','tracker-save'), items=[];
      if(r)items.push([r,'secondary']); if(s)items.push([s,'primary']);
      return items.length?{key:'tracker',v,layout:items.length===2?'pair':'single',items}:null;
    }
    return null;
  };
  const suppressLoginActions = () => {
    const strip=document.querySelector('.centralos-mobile-action-strip');
    if(!logged()) {
      strip?.removeAttribute('data-visible');
      if(strip) strip.style.setProperty('display','none','important');
      document.querySelector('.centralos-home-mobile-action-zone')?.remove();
    } else if(strip?.style.getPropertyValue('display')==='none') strip.style.removeProperty('display');
  };
  const syncActions = () => {
    suppressLoginActions();
    if(!logged()){ if(active.length) restoreActive(); else removeZone(); return; }
    if(!mq.matches){
      if(active.length) restoreActive();
      const p=prepHome(); if(p?.a&&p.a.parentElement!==p.h) p.f?p.f.after(p.a):p.h.appendChild(p.a);
      return;
    }
    const d=desired();
    if(!d){ if(active.length) restoreActive(); else removeZone(); return; }
    const z=ensureZone(); if(!z) return;
    const nodes=d.items.map(x=>x[0]);
    if(activeKey===d.key && nodes.length===active.length && nodes.every((n,i)=>n===active[i]&&n.parentElement===z)) {
      z.dataset.visible=''; z.dataset.layout=d.layout; z.dataset.view=d.v; return;
    }
    if(active.length) restoreActive();
    const fresh=ensureZone(); if(!fresh) return;
    d.items.forEach(([node,role])=>{
      remember(node);
      if(node.tagName==='BUTTON'){
        keepForm(node); node.classList.add('centralos-mobile-action-button',role==='secondary'?'centralos-mobile-action-secondary':'centralos-mobile-action-primary');
      } else node.classList.add('centralos-mobile-home-split');
      fresh.appendChild(node);
    });
    active=nodes; activeKey=d.key; fresh.dataset.visible=''; fresh.dataset.layout=d.layout; fresh.dataset.view=d.v;
  };

  const css = `
.centralos-mobile-view-action-zone{display:none}
@media(max-width:767px){
 .centralos-mobile-view-action-zone[data-visible]{display:grid!important;grid-template-columns:1fr;gap:8px;width:100%;padding:0 14px 12px;background:#0b0e12;position:relative;z-index:55}
 .centralos-mobile-view-action-zone[data-layout="pair"]{grid-template-columns:minmax(0,.8fr) minmax(0,1.2fr)}
 .centralos-mobile-action-button{width:100%!important;min-width:0!important;height:50px!important;margin:0!important;padding:0 16px!important;display:flex!important;align-items:center!important;justify-content:center!important;gap:10px!important;border-radius:12px!important;font-size:15px!important;font-weight:800!important;white-space:nowrap!important}
 .centralos-mobile-action-primary{border:1px solid #ff6500!important;background:linear-gradient(90deg,#ff6500,#ff5a00)!important;color:#fff!important;box-shadow:0 10px 24px rgba(255,101,0,.18)!important}
 .centralos-mobile-action-secondary{border:1px solid #343b45!important;background:#171b21!important;color:#fff!important}
 .centralos-mobile-view-action-zone>.centralos-dashboard-open-action{display:grid!important;grid-template-columns:minmax(0,1fr) 50px!important;width:100%!important;margin:0!important;padding:0!important;border-radius:12px!important;box-shadow:0 10px 24px rgba(255,101,0,.18)!important;overflow:visible!important}
 .centralos-mobile-view-action-zone .centralos-dashboard-open-primary{height:50px!important;margin:0!important;border:0!important;border-radius:12px 0 0 12px!important;background:linear-gradient(90deg,#ff6500,#ff5a00)!important;color:#fff!important;font-size:17px!important;font-weight:800!important;display:flex!important;align-items:center!important;justify-content:center!important;gap:14px!important}
 .centralos-mobile-view-action-zone .centralos-dashboard-open-more:not([style*="display: none"]){width:50px!important;height:50px!important;margin:0!important;border:0!important;border-left:1px solid rgba(255,255,255,.26)!important;border-radius:0 12px 12px 0!important;background:linear-gradient(90deg,#ff6500,#ff5a00)!important;color:#fff!important;display:flex!important;align-items:center!important;justify-content:center!important}
 .centralos-mobile-view-action-zone .centralos-dashboard-open-more[style*="display: none"]{display:none!important}
 .centralos-mobile-view-action-zone .centralos-dashboard-open-more>i{transform:rotate(-90deg)!important}
 .centralos-mobile-view-action-zone .centralos-dashboard-open-menu{right:0!important;top:calc(100% + 8px)!important;z-index:100!important}
 body.centralos-enhanced .centralos-dashboard>header{display:flex!important;flex-direction:column!important;align-items:stretch!important;width:100%!important;margin-bottom:14px!important}
 body.centralos-enhanced .centralos-dashboard>header>.centralos-dashboard-filter-shell{display:block!important;width:100%!important;margin-top:14px!important;padding:0!important;overflow:hidden!important}
 body.centralos-enhanced .centralos-dashboard .centralos-period-filter{display:flex!important;width:100%!important;gap:8px!important;padding:0 0 4px!important;margin:0!important;overflow-x:auto!important;background:transparent!important;border:0!important;scrollbar-width:none}
 body.centralos-enhanced .centralos-dashboard .centralos-period-filter::-webkit-scrollbar{display:none}
 body.centralos-enhanced .centralos-dashboard .centralos-period-filter .centralos-period-button{flex:0 0 auto!important;width:auto!important;min-height:37px!important;padding:7px 13px!important;border:1px solid #dfe3e8!important;border-radius:999px!important;background:#fff!important;color:#68717d!important;font-size:12px!important;font-weight:650!important;white-space:nowrap!important}
}
@media(min-width:768px){body.centralos-enhanced .centralos-dashboard>header{display:grid!important;grid-template-columns:max-content minmax(0,1fr) max-content!important;align-items:center!important;column-gap:18px!important}.centralos-dashboard-open-more>i{transform:none!important}}
body.centralos-auth-actions-hidden .centralos-mobile-view-action-zone,body.centralos-auth-actions-hidden .centralos-mobile-action-strip,body.centralos-auth-actions-hidden .centralos-home-mobile-action-zone{display:none!important;visibility:hidden!important;pointer-events:none!important}`;
  const ensureStyle = () => {
    for(let i=2;i<=10;i++) document.getElementById(`centralos-layout-fixes-v${i}`)?.remove();
    if(document.getElementById('centralos-layout-fixes-v11')) return;
    const s=document.createElement('style'); s.id='centralos-layout-fixes-v11'; s.textContent=css; document.head.appendChild(s);
  };
  const decorate = () => {
    ensureStyle();
    document.body.classList.toggle('centralos-auth-actions-hidden',!logged());
    const d=dashboard();
    if(d){
      prepHome();
      const defs=[['aguardando início','centralos-queue-tech','fa-user-gear'],['pendente envio','centralos-queue-outsourced-send','fa-paper-plane'],['aguardando retorno','centralos-queue-outsourced-return','fa-rotate-left'],['aguardando compra','centralos-queue-supplier-purchase','fa-cart-shopping'],['aguardando recebimento','centralos-queue-supplier-receipt','fa-box-open'],['aguardando teste final','centralos-queue-final-test','fa-flask'],['sem agendamento','centralos-queue-unscheduled','fa-calendar-xmark']];
      [...d.querySelectorAll('h4')].forEach(h=>{const x=defs.find(a=>norm(h.textContent).includes(norm(a[0])));if(!x)return;const c=h.closest('.bg-white');if(!c)return;c.classList.add('centralos-queue','centralos-queue--extended',x[1]);h.classList.add('centralos-queue-title');if(!h.querySelector(':scope>.centralos-queue-icon')){const e=document.createElement('span');e.className='centralos-queue-icon';e.innerHTML=`<i class="fa-solid ${x[2]}"></i>`;h.prepend(e);}});
    }
    syncActions();
  };
  const schedule = () => { if(raf)return; raf=requestAnimationFrame(()=>{raf=0;decorate();}); };
  const start = () => {
    ensureStyle(); decorate(); setTimeout(decorate,100); setTimeout(decorate,300); setTimeout(decorate,900);
    document.addEventListener('click',()=>setTimeout(decorate,0),{passive:true}); mq.addEventListener?.('change',decorate);
    new MutationObserver(schedule).observe(document.body,{childList:true,subtree:true,attributes:true,attributeFilter:['style','x-cloak','data-visible']});
    setInterval(suppressLoginActions,500);
  };
  document.readyState==='loading'?document.addEventListener('DOMContentLoaded',start,{once:true}):start();
})();
