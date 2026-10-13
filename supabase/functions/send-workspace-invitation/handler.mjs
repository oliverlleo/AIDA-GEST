import {HttpError, UUID, authenticate, adminContext, rpc, jsonResponse, escapeHtml, withErrors, readLimitedBody} from '../_shared/auth-http.mjs';

/**
 * @param {(name: string) => string | undefined} env
 * @param {typeof fetch} fetcher
 * @param {null | ((message: any, config: any) => Promise<any>)} sendMail
 */
export function createHandler(env, fetcher = fetch, sendMail = null) {
  return withErrors(async (request, config, headers, fetcher) => {
    const identity = await authenticate(request, config, fetcher);
    let body;
    const bytes = await readLimitedBody(request, 4096);
    try { body = JSON.parse(new TextDecoder().decode(bytes)); } catch { throw new HttpError(400, 'invalid_request'); }
    if (!UUID.test(body?.invitation_id || '')) throw new HttpError(400, 'invitation_required');
    const workspaceId = body.workspace_id || request.headers.get('x-workspace-id');
    await adminContext(config, identity, workspaceId, fetcher);
    const params = {p_invitation_id: body.invitation_id, p_requester_user_id: identity.user.id};
    const invitation = await rpc(config, 'get_invitation_delivery_details', params, null, null, fetcher);
    if (!invitation || invitation.workspace_id !== workspaceId) throw new HttpError(403, 'access_denied');

    const mark = (accepted, error) => rpc(config, 'mark_invitation_delivery', {
      ...params, p_delivery_attempt_id: invitation.delivery_attempt_id, p_delivered: accepted, p_error_code: error || null,
    }, null, null, fetcher);
    if (!config.smtpHost || !config.smtpUser || !config.smtpPassword || !config.senderEmail || !sendMail) {
      await mark(false, 'email_configuration_missing');
      return jsonResponse({sent: false, status: 'failed', error_code: 'email_configuration_missing'}, 503, headers);
    }
    const link = new URL(config.appUrl);
    link.searchParams.set('invitation', body.invitation_id);
    const company = String(invitation.workspace_name || 'sua empresa');
    const message = {
      from: {name: config.senderName, address: config.senderEmail},
      to: [{address: invitation.email, name: invitation.name}],
      subject: `Convite para ${company.replace(/[\r\n]/g, ' ')} — CentralOS`,
      html: `<p>Olá, ${escapeHtml(invitation.name)}.</p><p>Você recebeu um convite para acessar <strong>${escapeHtml(company)}</strong>.</p><p><a href="${escapeHtml(link.href)}">Entrar e revisar o convite</a></p><p>Entre ou crie sua conta com o e-mail que recebeu este convite. Você também poderá aceitá-lo dentro do aplicativo após confirmar seu e-mail.</p><p>O convite tem validade de sete dias. Se não esperava este convite, ignore a mensagem.</p>`,
      text: `Olá, ${invitation.name}. Você recebeu um convite para ${company}. Entre ou crie uma conta com este e-mail e revise o convite: ${link.href}. O convite tem validade de sete dias.`,
    };
    try {
      const result = await sendMail(message, config);
      if (!Array.isArray(result?.accepted) || !result.accepted.includes(invitation.email)) throw new Error('Recipient not accepted');
    } catch {
      await mark(false, 'email_provider_unavailable');
      return jsonResponse({sent: false, status: 'failed', error_code: 'email_provider_unavailable'}, 502, headers);
    }
    // Provider accepted the request. This does not assert inbox delivery.
    await mark(true, null);
    return jsonResponse({sent: true, status: 'queued'}, 200, headers);
  }, env, fetcher);
}
