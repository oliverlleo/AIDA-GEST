const test=require('node:test'),assert=require('node:assert/strict');global.window=global;require('../js/modules/api-client.js');require('../js/modules/employee-service.js');const s=global.AIDAEmployeeService;
test('sessão Auth de técnico não concede administração',()=>{assert.equal(s.isAdmin({session:{access_token:'jwt'},user:{roles:['tecnico']}}),false);assert.equal(s.isAdmin({user:{roles:['admin']}}),true);});
test('atendente recebe diretório seguro sem credenciais',async()=>{const state={user:{workspace_id:'ws',roles:['atendente']}};let endpoint;await s.fetchEmployees({state,supabaseFetch:async ep=>{endpoint=ep;return[{name:'Ana'}];}});assert.match(endpoint,/^employees\?/);assert.match(endpoint,/legacy_auth_disabled=eq.false/);assert.ok(!/password|auth_user_id/.test(endpoint));assert.equal(state.employees[0].name,'Ana');});
test('gestor lista funcionários e convites na empresa ativa',async()=>{const state={user:{workspace_id:'ws',roles:['admin']}},calls=[];await s.fetchEmployees({state,supabaseFetch:async(ep,_m,p)=>{calls.push({ep,p});return ep.includes('staff')?[{name:'Ana',access_status:'blocked'}]:[];}});assert.equal(calls[0].ep,'rpc/list_workspace_staff');assert.equal(calls[1].ep,'rpc/get_my_workspace_invitations');assert.deepEqual(calls[0].p,{p_workspace_id:'ws'});assert.equal(state.employees[0].manual_blocked,true);});
test('convite inválido é barrado antes do servidor',async()=>{let called=false,notice;await s.createEmployee({state:{user:{workspace_id:'ws',roles:['admin']},employeeForm:{name:'Ana',email:'invalid',roles:['tecnico']}},supabaseFetch:async()=>{called=true;},notify:m=>notice=m});assert.equal(called,false);assert.match(notice,/e-mail válido/);});
test('gestor não possui API para alterar senha de outra conta',()=>{assert.equal(s.resetEmployeePassword,undefined);assert.equal(s.changeOwnPassword,undefined);});
test('sem SMTP é exibido link e pendência de configuração',()=>{let notice,type;s.notifyDelivery({sent:false,status:'pending_configuration'},(m,t)=>{notice=m;type=t;});assert.match(notice,/Copie o link/);assert.notEqual(type,'error');});

test('funcionário removido não reaparece no diretório nem na atribuição de técnicos',async()=>{
 const state={user:{workspace_id:'ws',roles:['admin']}};
 await s.fetchEmployees({state,supabaseFetch:async endpoint=>endpoint.includes('staff')?[
  {id:'removed',name:'Antigo',roles:['tecnico'],access_status:'removed'},
  {id:'active',name:'Atual',roles:['tecnico'],access_status:'active'}
 ]:[]});
 assert.deepEqual(state.employees.map(employee=>employee.id),['active']);
});

test('envio limitado preserva convite criado e oferece link sem reenviar automaticamente', async(t)=>{
 const originalFetch=global.fetch;
 t.after(()=>{global.fetch=originalFetch;});
 const state={user:{workspace_id:'ws',roles:['admin']},session:{access_token:'jwt'},employeeForm:{name:'Ana',email:'ana@example.test',roles:['tecnico']}};
 const calls=[],notices=[];let closed=false,refreshed=false;
 global.fetch=async(url,options)=>{
  calls.push({url,options});
  return new Response('{}',{status:429,headers:{'Retry-After':'19'}});
 };
 await s.createEmployee({state,SUPABASE_URL:'https://example.supabase.co',SUPABASE_KEY:'public-key',
  supabaseFetch:async(endpoint)=>{assert.equal(endpoint,'rpc/create_workspace_invitation');return 'saved-invitation';},
  notify:message=>notices.push(message),setLoading:()=>{},closeModal:()=>{closed=true;},fetchEmployees:async()=>{refreshed=true;}
 });
 assert.equal(calls.length,1);
 assert.equal(JSON.parse(calls[0].options.body).invitation_id,'saved-invitation');
 assert.ok(notices.some(message=>/Convite salvo/.test(message)&&/19 segundos/.test(message)&&/copiar o link/.test(message)));
 assert.equal(closed,true);assert.equal(refreshed,true);
});
