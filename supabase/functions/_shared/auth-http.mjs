export class HttpError extends Error {
  constructor(status, code) { super(code); this.status = status; this.code = code; }
}

export const APP_URL = 'https://techassist.pages.dev/app.html';
export const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function configuration(env) {
  const app = new URL(env('APP_URL') || APP_URL);
  if (app.protocol !== 'https:' || app.search || app.hash) throw new HttpError(503, 'invalid_app_configuration');
  return {
    url: env('SUPABASE_URL'), anonKey: env('SUPABASE_ANON_KEY'),
    serviceKey: env('SUPABASE_SERVICE_ROLE_KEY'), appUrl: app.href, origin: app.origin,
    allowedOrigins: [app.origin, 'https://oliverlleo.github.io'],
    smtpHost: env('SMTP_HOST'), smtpPort: Number(env('SMTP_PORT') || 465),
    smtpUser: env('SMTP_USER'), smtpPassword: env('SMTP_PASSWORD'),
    senderEmail: env('SMTP_SENDER_EMAIL'), senderName: env('SMTP_SENDER_NAME') || 'CentralOS',
  };
}

export function cors(request, config) {
  const origin = request.headers.get('origin');
  if (origin && !config.allowedOrigins.includes(origin)) throw new HttpError(403, 'origin_not_allowed');
  return {
    'Access-Control-Allow-Origin': origin || config.origin,
    'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-workspace-id',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Max-Age': '600', 'Vary': 'Origin',
    'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff',
  };
}

export function jsonResponse(value, status = 200, headers = {}) {
  return new Response(JSON.stringify(value), {status, headers: {...headers, 'Content-Type': 'application/json; charset=utf-8'}});
}

export async function authenticate(request, config, fetcher = fetch) {
  const authorization = request.headers.get('authorization') || '';
  if (!/^Bearer [^\s]+$/i.test(authorization) || authorization.length > 10000) throw new HttpError(401, 'authentication_required');
  if (!config.url || !config.anonKey || !config.serviceKey) throw new HttpError(503, 'server_configuration_missing');
  const response = await fetcher(`${config.url}/auth/v1/user`, {
    headers: {apikey: config.anonKey, Authorization: authorization},
  });
  if (!response.ok) throw new HttpError(401, 'invalid_session');
  const user = await response.json();
  if (!UUID.test(user.id || '')) throw new HttpError(401, 'invalid_session');
  return {user, authorization};
}

export async function rpc(config, name, body, authorization, workspaceId, fetcher = fetch) {
  const headers = {'Content-Type': 'application/json', apikey: authorization ? config.anonKey : config.serviceKey,
    Authorization: authorization || `Bearer ${config.serviceKey}`};
  if (workspaceId) headers['x-workspace-id'] = workspaceId;
  const response = await fetcher(`${config.url}/rest/v1/rpc/${name}`, {
    method: 'POST', headers, body: JSON.stringify(body),
  });
  if (!response.ok) {
    // Never return database/provider bodies: they can contain addresses or credentials.
    const status = response.status === 429 ? 429 : response.status === 409 ? 409 : 403;
    throw new HttpError(status, status === 429 || status === 409 ? 'delivery_retry_later' : 'access_denied');
  }
  const text = await response.text();
  return text ? JSON.parse(text) : null;
}

export async function adminContext(config, identity, workspaceId, fetcher = fetch) {
  if (!UUID.test(workspaceId || '')) throw new HttpError(400, 'workspace_required');
  const context = await rpc(config, 'get_my_access_context', {p_workspace_id: workspaceId}, identity.authorization, workspaceId, fetcher);
  if (!context || context.workspace_id !== workspaceId || !(context.roles || []).includes('admin')) throw new HttpError(403, 'admin_required');
  return context;
}

export function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, char => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'}[char]));
}

export async function readLimitedBody(request, limit) {
  if (Number(request.headers.get('content-length') || 0) > limit) throw new HttpError(413, 'request_too_large');
  if (!request.body) return new Uint8Array();
  const reader = request.body.getReader();
  const chunks = [];
  let size = 0;
  try {
    for (;;) {
      const {done, value} = await reader.read();
      if (done) break;
      size += value.length;
      if (size > limit) { await reader.cancel(); throw new HttpError(413, 'request_too_large'); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  return bytes;
}

export function withErrors(handler, env, fetcher = fetch) {
  return async request => {
    let headers = {};
    try {
      const config = configuration(env);
      headers = cors(request, config);
      if (request.method === 'OPTIONS') return new Response(null, {status: 204, headers});
      if (request.method !== 'POST') throw new HttpError(405, 'method_not_allowed');
      return await handler(request, config, headers, fetcher);
    } catch (error) {
      const safe = error instanceof HttpError ? error : new HttpError(500, 'request_failed');
      return jsonResponse({error_code: safe.code}, safe.status, headers);
    }
  };
}
