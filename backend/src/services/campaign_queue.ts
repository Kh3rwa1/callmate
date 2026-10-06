/**
 * Campaign Queue Service for asynchronous call dispatch via Cloudflare Queues
 */

import { Env } from '../types';
import { checkCallCompliance } from './compliance';

export interface CampaignJobMessage {
  campaign_id: string;
  lead_id: string;
  business_id: string;
  idempotency_key: string;
  attempts: number;
}

export interface ProcessResult {
  success: boolean;
  retry?: boolean;
  delaySeconds?: number;
  reason?: string;
}

const MAX_CONCURRENT_CALLS_PER_BUSINESS = 5;

/**
 * Processes a single campaign lead call job from the queue.
 */
export async function processCampaignJob(
  env: Env,
  job: CampaignJobMessage
): Promise<ProcessResult> {
  const { campaign_id, lead_id, business_id } = job;

  // 1. Check Campaign Status
  const campaign = await env.DB.prepare(
    'SELECT status, calling_hours_start, calling_hours_end FROM campaigns WHERE id = ? AND business_id = ?'
  ).bind(campaign_id, business_id).first<{
    status: string;
    calling_hours_start: number;
    calling_hours_end: number;
  }>();

  if (!campaign || campaign.status !== 'running') {
    // Campaign was paused or stopped: do not place call
    return { success: true, reason: 'campaign_stopped' };
  }

  // 2. Check Lead & Campaign Lead Status (Idempotency)
  const campLead = await env.DB.prepare(
    'SELECT status, attempts FROM campaign_leads WHERE campaign_id = ? AND lead_id = ?'
  ).bind(campaign_id, lead_id).first<{ status: string; attempts: number }>();

  if (!campLead) {
    return { success: true, reason: 'lead_not_in_campaign' };
  }

  if (['calling', 'completed', 'skipped_dnc', 'max_attempts_exceeded'].includes(campLead.status)) {
    return { success: true, reason: 'already_processed' };
  }

  // 3. Check Per-Business Concurrency Limit
  const activeCalls = await env.DB.prepare(
    `SELECT COUNT(*) as count FROM calls
     WHERE business_id = ? AND status = 'calling' AND started_at > datetime('now', '-20 minutes')`
  ).bind(business_id).first<{ count: number }>();

  if (activeCalls && activeCalls.count >= MAX_CONCURRENT_CALLS_PER_BUSINESS) {
    console.log(`[Queue Throttle] Business ${business_id} at concurrency cap (${activeCalls.count}). Retrying...`);
    return { success: false, retry: true, delaySeconds: 15, reason: 'concurrency_limit_reached' };
  }

  // 4. Fetch Lead Details
  const lead = await env.DB.prepare(
    'SELECT * FROM leads WHERE id = ? AND business_id = ?'
  ).bind(lead_id, business_id).first<any>();

  if (!lead) {
    return { success: true, reason: 'lead_not_found' };
  }

  // 5. Compliance Guardrails (Calling Hours, DNC, Daily Attempts)
  const compliance = await checkCallCompliance(env.DB, {
    businessId: business_id,
    leadId: lead_id,
    campaignId: campaign_id,
    hoursStart: campaign.calling_hours_start,
    hoursEnd: campaign.calling_hours_end,
    timezone: lead.timezone || 'Asia/Kolkata',
  });

  if (!compliance.allowed) {
    if (compliance.reason === 'outside_hours') {
      await env.DB.prepare(
        `UPDATE campaign_leads SET status = 'rescheduled' WHERE campaign_id = ? AND lead_id = ?`
      ).bind(campaign_id, lead_id).run();
      return { success: false, retry: true, delaySeconds: compliance.rescheduleDelaySeconds || 3600, reason: 'outside_hours' };
    }

    if (compliance.reason === 'do_not_call') {
      await env.DB.prepare(
        `UPDATE campaign_leads SET status = 'skipped_dnc' WHERE campaign_id = ? AND lead_id = ?`
      ).bind(campaign_id, lead_id).run();
      return { success: true, reason: 'skipped_dnc' };
    }

    if (compliance.reason === 'max_daily_attempts' || compliance.reason === 'max_campaign_attempts') {
      await env.DB.prepare(
        `UPDATE campaign_leads SET status = 'max_attempts_exceeded' WHERE campaign_id = ? AND lead_id = ?`
      ).bind(campaign_id, lead_id).run();
      return { success: true, reason: compliance.reason };
    }
  }

  // 6. Billing Guardrail Check
  const usage = await env.DB.prepare(
    'SELECT included_minutes, minutes_used FROM usage WHERE business_id = ?'
  ).bind(business_id).first<{ included_minutes: number; minutes_used: number }>();

  if (usage && (usage.included_minutes - usage.minutes_used) <= 0) {
    // Insufficient minutes: pause campaign
    await env.DB.prepare(
      `UPDATE campaigns SET status = 'paused' WHERE id = ? AND business_id = ?`
    ).bind(campaign_id, business_id).run();
    return { success: false, retry: false, reason: 'exhausted_minutes' };
  }

  // 7. Place Call
  const callId = `call_${crypto.randomUUID().slice(0, 12)}`;

  // Record active call
  await env.DB.prepare(`
    INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, status, started_at, created_at)
    VALUES (?, ?, ?, ?, ?, 'calling', datetime('now'), datetime('now'))
  `).bind(callId, business_id, lead.id, lead.name, lead.phone).run();

  await env.DB.prepare(
    `UPDATE campaign_leads SET status = 'calling', attempts = attempts + 1, last_attempt_at = datetime('now')
     WHERE campaign_id = ? AND lead_id = ?`
  ).bind(campaign_id, lead_id).run();

  await env.DB.prepare(
    `UPDATE leads SET status = 'calling', updated_at = datetime('now') WHERE id = ? AND business_id = ?`
  ).bind(lead_id, business_id).run();

  // Call Sarvam API if configured
  const sarvamApiKey = env.SARVAM_API_KEY;
  const orgId = env.SARVAM_ORG_ID || 'org_callpilot';
  const workspaceId = env.SARVAM_WORKSPACE_ID || 'ws_callpilot';
  const appId = env.SARVAM_ADMISSIONS_APP_ID || 'app_callpilot_voice';

  if (sarvamApiKey && !sarvamApiKey.startsWith('mock-')) {
    const business = await env.DB.prepare('SELECT * FROM businesses WHERE id = ?').bind(business_id).first<any>();
    const agent = await env.DB.prepare('SELECT * FROM agents WHERE business_id = ?').bind(business_id).first<any>();

    try {
      const sarvamRes = await fetch(
        `https://apps.sarvam.ai/api/outbounds/v1/orgs/${orgId}/workspaces/${workspaceId}/outbounds`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-API-Key': sarvamApiKey,
          },
          body: JSON.stringify({
            app_config: { app_id: appId },
            user_config: { phone_number: lead.phone },
            agent_variables: {
              call_id: callId,
              campaign_id: campaign_id,
              lead_id: lead.id,
              lead_name: lead.name,
              business_name: business?.name || 'CallPilot Business',
              agent_name: agent?.name || 'Riya',
              agent_role: agent?.role || 'Assistant',
              course_interest: lead.course_interest || lead.interest || '',
            },
          }),
        }
      );

      const resData: any = await sarvamRes.json().catch(() => null);
      if (resData?.interaction_id || resData?.id || resData?.attempt_id) {
        const interactionId = resData.interaction_id || resData.id || resData.attempt_id;
        await env.DB.prepare(
          'UPDATE calls SET interaction_id = ? WHERE id = ? AND business_id = ?'
        ).bind(interactionId, callId, business_id).run();
      }
    } catch (err: any) {
      console.error(`[Sarvam Queue Outbound Error] Lead ${lead.id}:`, err?.message || err);
      if (job.attempts < 3) {
        return { success: false, retry: true, delaySeconds: 30, reason: err?.message };
      }
      await env.DB.prepare(
        `UPDATE campaign_leads SET status = 'failed', error = ? WHERE campaign_id = ? AND lead_id = ?`
      ).bind(String(err?.message || err), campaign_id, lead_id).run();
    }
  }

  return { success: true };
}

/**
 * Enqueues jobs for a campaign. Uses Cloudflare Queue if bound, or processes asynchronously.
 */
export async function enqueueCampaignJobs(
  env: Env,
  campaignId: string,
  businessId: string,
  leadIds: string[]
): Promise<void> {
  const messages: CampaignJobMessage[] = leadIds.map((lid) => ({
    campaign_id: campaignId,
    lead_id: lid,
    business_id: businessId,
    idempotency_key: `${campaignId}:${lid}`,
    attempts: 0,
  }));

  // Update campaign_leads to 'queued'
  for (const lid of leadIds) {
    await env.DB.prepare(
      `UPDATE campaign_leads SET status = 'queued' WHERE campaign_id = ? AND lead_id = ?`
    ).bind(campaignId, lid).run();
  }

  console.log(`[enqueueCampaignJobs] CAMPAIGN_QUEUE exists: ${!!env.CAMPAIGN_QUEUE}, total messages: ${messages.length}`);
  if (env.CAMPAIGN_QUEUE) {
    const queueBatches: { body: CampaignJobMessage }[] = messages.map((m) => ({ body: m }));
    const chunkSize = 100;
    for (let i = 0; i < queueBatches.length; i += chunkSize) {
      await env.CAMPAIGN_QUEUE.sendBatch(queueBatches.slice(i, i + chunkSize));
    }
  } else {
    // Process jobs immediately/asynchronously when queue binding is not present
    for (const msg of messages) {
      await processCampaignJob(env, msg);
    }
  }
}

/**
 * Consumer handler for Cloudflare Queues
 */
export async function handleCampaignQueueBatch(
  batch: MessageBatch<CampaignJobMessage>,
  env: Env
): Promise<void> {
  console.log(`[handleCampaignQueueBatch] Consumer triggered with ${batch?.messages?.length} messages`);
  for (const message of batch.messages) {
    const result = await processCampaignJob(env, message.body);
    if (result.success) {
      message.ack();
    } else if (result.retry) {
      message.retry({ delaySeconds: result.delaySeconds || 30 });
    } else {
      // Unrecoverable (e.g. out of minutes): acknowledge to stop retry loop
      message.ack();
    }
  }
}
