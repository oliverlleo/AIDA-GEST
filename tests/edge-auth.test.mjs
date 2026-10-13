import test from 'node:test';
import assert from 'node:assert/strict';
import {createHandler as buildInvitationHandler} from '../supabase/functions/send-workspace-invitation/handler.mjs';
import {createHandler as createLogoHandler} from '../supabase/functions/upload-workspace-logo/handler.mjs';

const WS = '11111111-1111-4111-8111-111111111111';
const OTHER = '22222222-2222-4222-8222-222222222222';
const USER = '33333333-3333-4333-8333-333333333333';
const INVITE = '44444444-4444-4444-8444-444444444444';
const ATTEMPT = '55555555-5555-4555-8555-555555555555';
const origin = 'https://oliverlleo.github.io';
const values = {SUPABASE_URL:'https://project.supabase.co', SUPABASE_ANON_KEY:'public-test-key',
  SUPABASE_SERVICE_ROLE_KEY:'server-test-key', SMTP_HOST:'smtp.example.test', SMTP_USER:'sender@example.test',
  SMTP_PASSWORD:'mail-test-key', SMTP_SENDER_EMAIL:'sender@example.test'};
const env = name => values[name];
const json = (value, status=200) => new Response(JSON.stringify(value), {status, headers:{'Content-Type':'application/json'}});
const createInvitationHandler = (env,fetcher) => buildInvitationHandler(env,fetcher,async message => {
  const response = await fetcher('smtp-test://delivery',{body:JSON.stringify(message)});
  if (!response.ok) throw new Error('private SMTP failure details');
  return await response.json();
});

function setup(overrides={}) {
  const calls=[];
  const fetcher = async (url, options={}) => {
    const body = typeof options.body === 'string' ? JSON.parse(options.body) : options.body;
    calls.push({url,options,body});
    if (url.endsWith('/auth/v1/user')) return overrides.user || json({id:USER});
    if (url.endsWith('/get_my_access_context')) return overrides.context || json({workspace_id:WS,roles:['admin']});
    if (url.endsWith('/get_invitation_delivery_details')) return overrides.details || json({
      workspace_id:WS, name:'Pessoa <script>', workspace_name:'Oficina & Cia',
      email:'staff@example.test',delivery_attempt_id:ATTEMPT,
    });
    if (url.endsWith('/mark_invitation_delivery')) return json(null);
    if (url === 'smtp-test://delivery') return overrides.provider || json({accepted:['staff@example.test']},201);
    if (url.includes('/storage/v1/object/')) return overrides.storage || json({Key:'test'});
    throw new Error(`Unexpected request ${url}`);
  };
  return {calls,fetcher};
}

function invitationRequest(headers={},body={invitation_id:INVITE,workspace_id:WS}) {
  return new Request('https://edge.test/send-workspace-invitation', {method:'POST',
    headers:{origin,Authorization:'Bearer caller-jwt','Content-Type':'application/json',...headers},body:JSON.stringify(body)});
}
function logoRequest(type='image/png',bytes=new Uint8Array([137,80,78,71,13,10,26,10])) {
  const form=new FormData();form.append('file',new File([bytes],'logo.png',{type}));
  return new Request('https://edge.test/upload-workspace-logo',{method:'POST',headers:{origin,Authorization:'Bearer caller-jwt','x-workspace-id':WS},body:form});
}

test('anonymous/legacy tokens cannot trigger invitation or logo operations',async()=>{
  for(const createHandler of [createInvitationHandler,createLogoHandler]) {
    const {calls,fetcher}=setup();
    const response=await createHandler(env,fetcher)(new Request('https://edge.test',{method:'POST',headers:{origin,'x-employee-token':INVITE}}));
    assert.equal(response.status,401);assert.equal(calls.length,0);
  }
});
test('a bearer token is verified by Auth before privileged requests',async()=>{
  const {calls,fetcher}=setup({user:json({error:'invalid'},401)});
  const response=await createInvitationHandler(env,fetcher)(invitationRequest());
  assert.equal(response.status,401);assert.equal(calls.length,1);
});
test('authenticated technician cannot send invitations or upload a logo',async()=>{
  for(const [createHandler,request] of [[createInvitationHandler,invitationRequest()],[createLogoHandler,logoRequest()]]) {
    const {calls,fetcher}=setup({context:json({workspace_id:WS,roles:['tecnico']})});
    const response=await createHandler(env,fetcher)(request);
    assert.equal(response.status,403);assert.equal(calls.length,2);
  }
});
test('owner in another company does not bypass the selected membership',async()=>{
  const {calls,fetcher}=setup({context:json({workspace_id:OTHER,roles:['admin']})});
  const response=await createInvitationHandler(env,fetcher)(invitationRequest());
  assert.equal(response.status,403);assert.equal(calls.length,2);
});
test('invitation must belong to the company validated using the caller JWT',async()=>{
  const {calls,fetcher}=setup({details:json({workspace_id:OTHER,email:'other@example.test'})});
  assert.equal((await createInvitationHandler(env,fetcher)(invitationRequest())).status,403);
  assert.equal(calls.length,3);
  assert.equal(calls[1].options.headers.Authorization,'Bearer caller-jwt');
  assert.equal(calls[1].options.headers['x-workspace-id'],WS);
  assert.equal(calls[2].options.headers.Authorization,'Bearer server-test-key');
  assert.equal(calls[2].body.p_requester_user_id,USER);
});
test('cancelled/expired/blocked invitation does not reach the provider',async()=>{
  const {calls,fetcher}=setup({details:json({message:'test sensitive body'},403)});
  const response=await createInvitationHandler(env,fetcher)(invitationRequest());
  assert.equal(response.status,403);assert.equal(calls.length,3);
  assert.ok(!(await response.text()).includes('sensitive'));
});
test('missing email configuration preserves failed invitation status',async()=>{
  const {calls,fetcher}=setup();
  const response=await createInvitationHandler(name=>name==='SMTP_PASSWORD'?null:env(name),fetcher)(invitationRequest());
  assert.equal(response.status,503);assert.equal(calls.length,4);
  assert.equal(calls.at(-1).body.p_error_code,'email_configuration_missing');
  assert.equal(calls.at(-1).body.p_delivery_attempt_id,ATTEMPT);
});
test('provider acceptance is reported as queued; content and link are safe',async()=>{
  const {calls,fetcher}=setup();
  const response=await createInvitationHandler(env,fetcher)(invitationRequest());
  assert.deepEqual(await response.json(),{sent:true,status:'queued'});
  const mail=calls.find(c=>c.url==='smtp-test://delivery').body;
  assert.ok(mail.html.includes('Pessoa &lt;script&gt;'));
  assert.ok(mail.html.includes(`app.html?invitation=${INVITE}`));
  assert.equal(mail.to[0].address,'staff@example.test');
  assert.equal(calls.at(-1).body.p_delivered,true);
});
test('provider failures are sanitized and can be retried',async()=>{
  const {calls,fetcher}=setup({provider:json({message:'secret/provider/address details'},429)});
  const response=await createInvitationHandler(env,fetcher)(invitationRequest());
  assert.equal(response.status,502);
  assert.deepEqual(await response.json(),{sent:false,status:'failed',error_code:'email_provider_unavailable'});
  assert.equal(calls.at(-1).body.p_delivered,false);
});
test('CORS does not authorize another origin and preflight sends nothing',async()=>{
  const {calls,fetcher}=setup();const handler=createInvitationHandler(env,fetcher);
  assert.equal((await handler(invitationRequest({origin:'https://other.test'}))).status,403);
  assert.equal((await handler(new Request('https://edge.test',{method:'OPTIONS',headers:{origin}}))).status,204);
  assert.equal(calls.length,0);
});
test('request limit is enforced even without content-length',async()=>{
  const {calls,fetcher}=setup();
  const response=await createInvitationHandler(env,fetcher)(invitationRequest({}, {invitation_id:INVITE,workspace_id:WS,extra:'x'.repeat(5000)}));
  assert.equal(response.status,413);assert.equal(calls.length,1);
});
test('logo upload uses the current company and caller JWT, not the service key',async()=>{
  const {calls,fetcher}=setup();
  const response=await createLogoHandler(env,fetcher)(logoRequest());
  assert.equal(response.status,200);const data=await response.json();
  assert.ok(data.path.startsWith(`${WS}/logo/`));assert.ok(data.path.endsWith('.png'));
  const upload=calls.at(-1);assert.equal(upload.options.headers.Authorization,'Bearer caller-jwt');
  assert.equal(upload.options.headers.apikey,'public-test-key');
  assert.equal(upload.options.headers['x-workspace-id'],WS);
});
test('HTML/SVG content cannot be uploaded as a public logo',async()=>{
  for(const type of ['image/svg+xml','image/png']) {
    const {calls,fetcher}=setup();
    const response=await createLogoHandler(env,fetcher)(logoRequest(type,new TextEncoder().encode('<script>alert(1)</script>')));
    assert.equal(response.status,400);assert.equal(calls.length,2);
  }
});
test('blocked/revoked membership cannot upload after Auth verifies identity',async()=>{
  const {calls,fetcher}=setup({context:json({message:'blocked'},403)});
  assert.equal((await createLogoHandler(env,fetcher)(logoRequest())).status,403);
  assert.equal(calls.length,2);
});
