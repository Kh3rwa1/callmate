import { Env } from '../types';
import { MAX_DIAL_ATTEMPTS, requeueLead, maybeCompleteCampaign } from './campaign_queue';
import { RETRY_SPACING_SECONDS } from './call_outcomes';

export async function runMaintenance(env: Env): Promise<void> {
  // 1. Prune rate-limit + idempotency tables
  await env.DB.batch([
    env.DB.prepare(`DELETE FROM otp_rate_limits WHERE created_at < datetime('now', '-1 day')`),
    env.DB.prepare(`DELETE FROM voice_proxy_rate_limits WHERE created_at < datetime('now', '-1 day')`),
    env.DB.prepare(`DELETE FROM push_rate_limits WHERE created_at < datetime('now', '-1 day')`),
    env.DB.prepare(`DELETE FROM rate_limits WHERE created_at < datetime('now', '-2 days')`),
    // Webhook idempotency keys are the replay guard: keep them well beyond any plausible redelivery window.
    env.DB.prepare(`DELETE FROM webhook_events WHERE received_at < datetime('now', '-90 days')`),
    // julianday() parses both ISO-8601 (with Z) and SQLite datetime formats
    env.DB.prepare(`DELETE FROM otp_codes WHERE julianday(expires_at) < julianday('now')`),
    env.DB.prepare(`DELETE FROM refresh_tokens_v2 WHERE julianday(expires_at) < julianday('now', '-1 day')`),
    env.DB.prepare(`UPDATE voice_sessions SET status = 'ended', ended_at = datetime('now')
                    WHERE status = 'active' AND started_at < datetime('now', '-1 hour')`),
  ]);

  // 2. Sweep stuck calls (no webhook within 45 min)
  const { results: stuck } = await env.DB.prepare(
    `SELECT c.id, c.business_id, cl.campaign_id, cl.lead_id, cl.attempts
     FROM calls c LEFT JOIN campaign_leads cl ON cl.call_id = c.id
     WHERE c.status = 'calling' AND c.started_at < datetime('now', '-45 minutes')
     LIMIT 200`
  ).all<any>();

  for (const s of stuck ?? []) {
    const retry = s.campaign_id && s.attempts < MAX_DIAL_ATTEMPTS;
    await env.DB.batch([
      env.DB.prepare(`UPDATE calls SET status = 'timed_out', failure_reason = 'no_webhook_45m' WHERE id = ?`).bind(s.id),
      ...(s.campaign_id ? [env.DB.prepare(`UPDATE campaign_leads SET status = ? WHERE call_id = ?`)
        .bind(retry ? 'retry_pending' : 'failed', s.id)] : []),
    ]);
    if (retry) await requeueLead(env, s.campaign_id, s.business_id, s.lead_id, RETRY_SPACING_SECONDS);
    else if (s.campaign_id) await maybeCompleteCampaign(env.DB, s.campaign_id);
  }
}
