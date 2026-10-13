import {HttpError, authenticate, adminContext, jsonResponse, withErrors, readLimitedBody} from '../_shared/auth-http.mjs';

const MAX_FILE_SIZE = 5 * 1024 * 1024;

function imageExtension(file, bytes) {
  const matches = {
    'image/png': bytes.length >= 8 && [137,80,78,71,13,10,26,10].every((v,i) => bytes[i] === v),
    'image/jpeg': bytes.length >= 3 && bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255,
    'image/webp': bytes.length >= 12 && String.fromCharCode(...bytes.subarray(0,4)) === 'RIFF' && String.fromCharCode(...bytes.subarray(8,12)) === 'WEBP',
    'image/gif': bytes.length >= 6 && /^GIF8[79]a$/.test(String.fromCharCode(...bytes.subarray(0,6))),
  };
  if (!matches[file.type]) throw new HttpError(400, 'unsupported_logo_image');
  return {'image/png':'png','image/jpeg':'jpg','image/webp':'webp','image/gif':'gif'}[file.type];
}

export function createHandler(env, fetcher = fetch) {
  return withErrors(async (request, config, headers, fetcher) => {
    const identity = await authenticate(request, config, fetcher);
    const workspaceId = request.headers.get('x-workspace-id');
    await adminContext(config, identity, workspaceId, fetcher);
    const bytes = await readLimitedBody(request, MAX_FILE_SIZE + 65536);
    let form;
    try { form = await new Response(bytes, {headers:{'Content-Type':request.headers.get('content-type') || ''}}).formData(); }
    catch { throw new HttpError(400, 'invalid_upload'); }
    const file = form.get('file');
    if (!(file instanceof File) || !file.size) throw new HttpError(400, 'logo_file_required');
    if (file.size > MAX_FILE_SIZE) throw new HttpError(413, 'logo_too_large');
    const fileBytes = new Uint8Array(await file.arrayBuffer());
    const ext = imageExtension(file, fileBytes);
    const path = `${workspaceId}/logo/logo_${crypto.randomUUID()}.${ext}`;
    // Use the caller's JWT so Storage rechecks membership and permissions at write time.
    const response = await fetcher(`${config.url}/storage/v1/object/workspace_logos/${path}`, {
      method: 'POST', headers: {apikey: config.anonKey, Authorization: identity.authorization,
        'Content-Type': file.type, 'x-upsert':'false', 'x-workspace-id': workspaceId}, body: fileBytes,
    });
    if (!response.ok) throw new HttpError(response.status === 403 ? 403 : 502, 'logo_upload_failed');
    return jsonResponse({success:true, path, publicUrl:`${config.url}/storage/v1/object/public/workspace_logos/${path}`}, 200, headers);
  }, env, fetcher);
}
