const test=require('node:test'),assert=require('node:assert/strict');
global.window=global;require('../js/modules/auth-session-service.js');
const s=global.AIDAAuthSessionService;
const U='11111111-1111-4111-8111-111111111111',W='22222222-2222-4222-8222-222222222222',E='33333333-3333-4333-8333-333333333333',I='44444444-4444-4444-8444-444444444444';
function setup(state={}){
 const storage=new Map(),events=[],calls=[];
 global.location={href:'https://oliverlleo.github.io/AIDA-GEST/app.html',replace:u=>events.push(['replace',u]),reload:()=>events.push(['reload'])};
 global.history={replaceState:(_s,_t,u)=>events.push(['clean',u])};
 global.localStorage={getItem:k=>storage.get(k)||null,setItem:(k,v)=>storage.set(k,v),removeItem:k=>storage.delete(k)};global.sessionStorage=global.localStorage;
 const d={state:{authForm:{email:'person@example.test',password:'Valid123'},registerForm:{email:'person@example.test',password:'Valid123'},...state},notify:m=>events.push(['notice',m]),setLoading:()=>{},supabaseFetch:async(ep,m,p)=>{calls.push({ep,m,p});return[];},supabaseClient:{auth:{},removeAllChannels:async()=>{}},bootstrapAuthenticatedApp:async()=>events.push(['bootstrap'])};
 return{d,storage,events,calls};
}

test('Cloudflare root entry resolves the invitation and confirmation to app.html',()=>{
 const {d}=setup({pendingInvitationId:I});global.location.href='https://techassist.pages.dev/';
 assert.equal(s.getAppUrl().href,'https://techassist.pages.dev/app.html');
 assert.equal(s.getEmailRedirectUrl(d.state),'https://techassist.pages.dev/app.html?auth=confirm&invitation='+I);
});
test('senha fraca é barrada antes de Auth',async()=>{const{d,events}=setup({registerForm:{email:'person@example.test',password:'12345678'}});d.supabaseClient.auth.signUp=async()=>{throw Error('must not run');};await s.register(d);assert.match(events[0][1],/letra e um número/);});
test('cadastro cria apenas identidade e pede confirmação',async()=>{const{d,calls}=setup({pendingInvitationId:I});let input;d.supabaseClient.auth.signUp=async x=>{input=x;return{data:{user:{id:U},session:null}};};await s.register(d);assert.equal(input.password,'Valid123');assert.ok(input.options.emailRedirectTo.includes(I));assert.equal(calls.length,0);assert.equal(d.state.user,undefined);assert.match(d.state.authNotice,/confirmar/);});
test('erro de login é genérico sem expor detalhes da conta',async()=>{const{d,events,calls}=setup();d.supabaseClient.auth.signInWithPassword=async()=>({error:{message:'internal secret account blocked'}});await s.login(d);assert.match(d.state.authError,/Não foi possível entrar/);assert.ok(!events.flat().join(' ').includes('internal secret'));assert.equal(calls.length,0);});
test('sem vínculo mostra convites e decisão explícita, sem criar empresa',async()=>{const{d,calls}=setup({session:{user:{id:U}}});d.supabaseFetch=async ep=>{calls.push(ep);return ep.includes('invitations')?[{invitation_id:I}]:[];};await s.loadAccessData(d);assert.equal(d.state.view,'access_hub');assert.equal(d.state.pendingInvitations.length,1);assert.equal(d.state.user,null);assert.equal(calls.length,2);});
test('técnico mantém ID funcional e nunca vira admin pela sessão',async()=>{const{d,events}=setup({session:{user:{id:U,email:'person@example.test'}}});await s.applyAccessContext({workspace_id:W,auth_user_id:U,member_kind:'employee',employee_id:E,roles:['tecnico'],name:'Ana'},d);assert.equal(d.state.user.id,E);assert.equal(d.state.user.auth_user_id,U);assert.deepEqual(d.state.user.roles,['tecnico']);assert.equal(d.state.employeeSession.token,undefined);assert.equal(d.state.view,'tech_orders');assert.ok(events.some(e=>e[0]==='bootstrap'));});
test('contexto de outra identidade é recusado antes do bootstrap',async()=>{const{d,events}=setup({session:{user:{id:U}}});await assert.rejects(s.applyAccessContext({workspace_id:W,auth_user_id:E,member_kind:'owner',roles:['admin']},d),/Acesso inválido/);assert.ok(!events.some(e=>e[0]==='bootstrap'));});
test('aceite conserva conta e lembra empresa nova sem sobrescrever proprietário',async()=>{const session={user:{id:U}}, {d,events,calls,storage}=setup({session,user:{workspace_id:'company-a'}});d.supabaseFetch=async(ep,m,p)=>{calls.push({ep,m,p});return W;};await s.acceptInvitation(I,d);assert.equal(d.state.session,session);assert.equal(storage.get(s.workspacePreferenceKey(U)),W);assert.equal(calls[0].ep,'rpc/accept_workspace_invitation');assert.equal(calls.length,1);assert.ok(events.some(e=>e[0]==='replace'));});
test('callback limpa token antes de verificar e preserva referência de convite',async()=>{const{d,events}=setup();global.location.href='https://oliverlleo.github.io/AIDA-GEST/app.html?auth=confirm&token_hash=secret&type=email&invitation='+I;d.supabaseClient.auth.verifyOtp=async()=>{assert.equal(events[0][0],'clean');assert.ok(!events[0][1].includes('secret'));return{data:{session:{user:{id:U}}}};};await s.handleAuthCallback(d);assert.equal(d.state.session.user.id,U);assert.equal(d.state.pendingInvitationId,I);assert.equal(d.state.recoveryMode,false);});
test('callback inválido não concede sessão',async()=>{const{d,events}=setup();global.location.href='https://oliverlleo.github.io/AIDA-GEST/app.html?token_hash=secret&type=admin';d.supabaseClient.auth.verifyOtp=async()=>{throw Error('must not run');};await s.handleAuthCallback(d);assert.equal(d.state.session,undefined);assert.ok(!events.flat().join(' ').includes('secret'));});
test('falha de rede não cria empresa automaticamente',async()=>{const{d}=setup({session:{user:{id:U}}});d.supabaseFetch=async()=>{throw Error('network');};await s.loadAccessData(d);assert.equal(d.state.view,'access_hub');assert.match(d.state.accessError,/verificar seu acesso/);});
test('troca de empresa valida servidor antes de persistir e recarregar',async()=>{const{d,events,storage}=setup({session:{user:{id:U}},workspaces:[{workspace_id:W}],user:null});d.supabaseFetch=async(ep,_m,p)=>{assert.equal(ep,'rpc/get_my_access_context');assert.equal(p.p_workspace_id,W);return{workspace_id:W};};await s.selectWorkspace(W,d);assert.equal(storage.get(s.workspacePreferenceKey(U)),W);assert.ok(events.some(e=>e[0]==='reload'));});

test('configuração parcial da empresa conserva defaults usados pela interface',async()=>{
 const{d}=setup({session:{user:{id:U}},trackerConfig:{logo_size:40,colors:{background:'#fff',icon_active:'#f60'},required_ticket_fields:{client_name:true}}});
 global.AIDAFeatureConfig={normalize:config=>config};
 await s.applyAccessContext({workspace_id:W,auth_user_id:U,member_kind:'owner',roles:['admin'],tracker_config:{colors:{background:'#eee'},test_flow:'tester'}},d);
 assert.equal(d.state.trackerConfig.colors.icon_active,'#f60');assert.equal(d.state.trackerConfig.colors.background,'#eee');assert.equal(d.state.trackerConfig.logo_size,40);assert.equal(d.state.trackerConfig.required_ticket_fields.client_name,true);
 delete global.AIDAFeatureConfig;
});

test('novo vínculo funcional na mesma empresa exige reload mesmo mantendo papéis',async()=>{
 const{d,events}=setup({session:{user:{id:U}}});
 const context={workspace_id:W,auth_user_id:U,member_kind:'employee',employee_id:E,membership_id:'original',roles:['tecnico']};
 await s.applyAccessContext(context,d);
 await s.applyAccessContext({...context,employee_id:I,membership_id:'recreated'},d);
 assert.ok(events.some(event=>event[0]==='reload'));
 assert.equal(events.filter(event=>event[0]==='bootstrap').length,1);
 assert.equal(d.state.user.id,E);
});
