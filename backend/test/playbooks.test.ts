import { describe, it, expect, beforeAll } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import app from '../src/index';
import { signJWT } from '../src/auth';
import { sarvamWebhookToken } from '../src/services/campaign_queue';
import {
  PLAYBOOKS,
  FOLLOWUP_OUTCOMES,
  playbookIdFor,
  playbookFor,
  followupOutcome,
  fillTemplate,
  playbookFollowupMessage,
  playbookCallContext,
  playbookPromptBlock,
  formatPlaybook,
  defaultFollowupDraft,
  type PlaybookId,
} from '../src/services/playbooks';
import { formatBusinessContext, buildCallAgentVariables, BUSINESS_CONTEXT_MAX_CHARS } from '../src/services/call_variables';
import { buildSystemPrompt } from '../src/services/prompt';

const SECRET = 'test-jwt-signing-secret-key-32chars-min-length';
const WEBHOOK_SECRET = 'test_webhook_secret_12345';
const BIZ = 'biz_pb_salon';
const BIZ_GEN = 'biz_pb_general';
const LANGS = ['en', 'hi', 'bn'] as const;

beforeAll(async () => {
  await migrateTestDb();
  await env.DB.batch([
    env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name, category) VALUES (?, 'Glow Salon', 'salon')").bind(BIZ),
    env.DB.prepare("INSERT OR REPLACE INTO users (id, phone, business_id) VALUES ('usr_pb', '919830055501', ?)").bind(BIZ),
    env.DB.prepare(
      "INSERT OR REPLACE INTO agents (id, business_id, name, role, status, languages) VALUES ('agt_pb', ?, 'Riya', 'Receptionist', 'active', '[\"Bengali\",\"English\"]')"
    ).bind(BIZ),
    env.DB.prepare("INSERT OR REPLACE INTO usage (id, business_id, plan_name, included_minutes, minutes_used) VALUES ('usg_pb', ?, 'Founding', 1000, 0)").bind(BIZ),
    env.DB.prepare('INSERT OR REPLACE INTO businesses (id, name) VALUES (?, ?)').bind(BIZ_GEN, 'Plain Shop'),
    env.DB.prepare("INSERT OR REPLACE INTO users (id, phone, business_id) VALUES ('usr_pb_gen', '919830055502', ?)").bind(BIZ_GEN),
  ]);
});

describe('playbook catalogue', () => {
  const ids = Object.keys(PLAYBOOKS) as PlaybookId[];

  it('has the six verticals, each complete in English, Hindi and Bengali', () => {
    expect(ids.sort()).toEqual(['education', 'fitness', 'general', 'healthcare', 'real_estate', 'salon']);
    for (const id of ids) {
      const p = PLAYBOOKS[id];
      expect(p.id).toBe(id);
      expect(p.qualifyingQuestions.length).toBeGreaterThanOrEqual(3);
      expect(p.qualifyingQuestions.length).toBeLessThanOrEqual(5);
      expect(p.objections.length).toBeGreaterThanOrEqual(2);
      expect(p.readyToBuy).toMatchObject({ temperature: 'hot', intents: ['interested'] });
      expect(p.callbackTiming.startHour).toBeLessThan(p.callbackTiming.endHour);
      expect(p.callbackTiming.startHour).toBeGreaterThanOrEqual(9);
      expect(p.callbackTiming.endHour).toBeLessThanOrEqual(21);
      const texts = [p.name, p.readyToBuy.description, p.callbackTiming.hint, ...p.qualifyingQuestions,
        ...p.objections.flatMap((o) => [o.objection, o.hint]), ...FOLLOWUP_OUTCOMES.map((k) => p.followups[k])];
      for (const t of texts) for (const l of LANGS) expect(t[l].trim().length).toBeGreaterThan(0);
      // Hindi in Devanagari, Bengali in Bengali script.
      expect(p.qualifyingQuestions[0].hi).toMatch(/[ऀ-ॿ]/);
      expect(p.qualifyingQuestions[0].bn).toMatch(/[ঀ-৿]/);
      for (const k of FOLLOWUP_OUTCOMES) {
        for (const l of LANGS) {
          expect(p.followups[k][l]).toContain('{name}');
          expect(p.followups[k][l]).toContain('{business}');
        }
      }
    }
  });

  it('maps categories (app wire values and synonyms) to playbooks', () => {
    expect(playbookIdFor('coaching')).toBe('education');
    expect(playbookIdFor('Education')).toBe('education');
    expect(playbookIdFor('clinic')).toBe('healthcare');
    expect(playbookIdFor('diagnostic')).toBe('healthcare');
    expect(playbookIdFor('real_estate')).toBe('real_estate');
    expect(playbookIdFor('Real Estate')).toBe('real_estate');
    expect(playbookIdFor('salon')).toBe('salon');
    expect(playbookIdFor('spa')).toBe('salon');
    expect(playbookIdFor('gym')).toBe('fitness');
    expect(playbookIdFor('restaurant')).toBe('general');
    expect(playbookIdFor(null)).toBe('general');
    expect(playbookFor('').id).toBe('general');
  });

  it('picks the follow-up outcome from the call output', () => {
    expect(followupOutcome({ temperature: 'hot', intent: 'interested' })).toBe('hot');
    expect(followupOutcome({ temperature: 'hot', callbackAt: '2026-10-11T10:00:00Z' })).toBe('callback');
    expect(followupOutcome({ temperature: 'warm', intent: 'callback_requested' })).toBe('callback');
    expect(followupOutcome({ temperature: 'warm', intent: 'not_interested' })).toBe('not_interested');
    expect(followupOutcome({ intent: 'opt_out' })).toBe('not_interested');
    expect(followupOutcome({ temperature: 'cold', intent: 'exploring' })).toBe('not_interested');
    expect(followupOutcome({ temperature: 'warm', intent: 'exploring' })).toBe('warm');
    expect(followupOutcome({})).toBe('warm');
  });

  it('fills {name} with the first name and {business}, literally', () => {
    expect(fillTemplate('Hi {name}, from {business}', { name: 'Asha Rao', business: 'Glow' })).toBe('Hi Asha, from Glow');
    expect(fillTemplate('Hi {name}, from {business}', { name: '', business: '' })).toBe('Hi, from us');
    expect(fillTemplate('नमस्ते {name}, {business}', { name: null, business: 'A $& B' })).toBe('नमस्ते, A $& B');
    expect(fillTemplate('{name} {name}', { name: '$1' })).toBe('$1 $1');
    expect(playbookFollowupMessage(PLAYBOOKS.fitness, 'hot', 'hi', { name: 'Ravi', business: 'Iron Gym' }))
      .toContain('नमस्ते Ravi, आपसे बात करके अच्छा लगा! Iron Gym में');
  });

  it('formats the playbook for the app in each language', () => {
    for (const l of LANGS) {
      const j = formatPlaybook(PLAYBOOKS.education, l, 'coaching');
      expect(j).toMatchObject({ id: 'education', category: 'coaching', language: l, name: PLAYBOOKS.education.name[l] });
      expect(j.qualifying_questions).toHaveLength(5);
      expect(j.ready_to_buy).toEqual({ description: PLAYBOOKS.education.readyToBuy.description[l], temperature: 'hot', intents: ['interested'], min_score: 75 });
      expect(Object.keys(j.followup_templates)).toEqual(['hot', 'warm', 'callback', 'not_interested']);
      expect(j.callback_timing).toMatchObject({ start_hour: 17, end_hour: 20 });
      expect(j.objections[0]).toEqual({ objection: PLAYBOOKS.education.objections[0].objection[l], hint: PLAYBOOKS.education.objections[0].hint[l] });
    }
  });
});

describe('playbook in the AI context', () => {
  it('business_context carries the questions and ready-to-buy definition within the cap', () => {
    const ctx = formatBusinessContext({ name: 'Iron Gym', category: 'gym' }, null, ['Open 6 am to 10 pm']);
    expect(ctx).toContain('Gym & fitness playbook');
    expect(ctx).toContain(PLAYBOOKS.fitness.qualifyingQuestions[0].en);
    expect(ctx).toContain(`Ready to buy: ${PLAYBOOKS.fitness.readyToBuy.description.en}`);
    expect(ctx.indexOf('Ready to buy')).toBeLessThan(ctx.indexOf('Open 6 am'));
    expect(ctx.length).toBeLessThanOrEqual(BUSINESS_CONTEXT_MAX_CHARS);

    // A huge knowledge base is cut, not the playbook.
    const big = Array.from({ length: 20 }, (_, i) => `Fact ${i} `.repeat(60));
    const capped = formatBusinessContext({ name: 'X', category: 'clinic', offerings: JSON.stringify(Array(200).fill('Dental')) }, null, big);
    expect(capped.length).toBeLessThanOrEqual(BUSINESS_CONTEXT_MAX_CHARS);
    expect(capped).toContain(`Ready to buy: ${PLAYBOOKS.healthcare.readyToBuy.description.en}`);
    expect(playbookCallContext(PLAYBOOKS.general)).toContain('1) What product or service');
  });

  it('is only sent when business_context is allow-listed (defaults unchanged)', async () => {
    const base = { businessId: BIZ, business: { name: 'Glow Salon' }, agent: null, lead: { id: 'l', name: 'n' }, callId: 'c', knowledge: [] };
    const defaults = await buildCallAgentVariables(env as any, base);
    expect(defaults.business_context).toBeUndefined();
    expect(Object.values(defaults).join(' ')).not.toContain('Ready to buy');
    const on = await buildCallAgentVariables({ ...env, SARVAM_AGENT_VARIABLES: 'business_context' } as any, base);
    expect(on.business_context).toContain('Salon & spa playbook');
  });

  it('the in-app chat prompt includes questions and objection hints', () => {
    const prompt = buildSystemPrompt({ agentName: 'Riya', agentRole: 'Receptionist', businessName: 'Glow', category: 'salon' });
    expect(prompt).toContain('CALL PLAYBOOK (Salon & spa)');
    expect(prompt).toContain(`1. ${PLAYBOOKS.salon.qualifyingQuestions[0].en}`);
    expect(prompt).toContain(`"${PLAYBOOKS.salon.objections[0].objection.en}": ${PLAYBOOKS.salon.objections[0].hint.en}`);
    expect(playbookPromptBlock(PLAYBOOKS.general)).toContain('Ready to buy means');
    expect(buildSystemPrompt({ agentName: 'A', agentRole: 'B', businessName: 'C' })).toContain('CALL PLAYBOOK (General)');
  });
});

describe('GET /playbooks/current', () => {
  const call = async (businessId: string, user: string, phone: string, q = '') => {
    const token = await signJWT({ sub: user, phone, business_id: businessId, type: 'access' }, SECRET, 3600);
    return app.fetch(new Request(`http://localhost/playbooks/current${q}`, { headers: { Authorization: `Bearer ${token}` } }), env);
  };

  it('requires auth', async () => {
    expect((await app.fetch(new Request('http://localhost/playbooks/current'), env)).status).toBe(401);
  });

  it("returns the business's playbook in the employee's language by default", async () => {
    const res = await call(BIZ, 'usr_pb', '919830055501');
    expect(res.status).toBe(200);
    const j = await res.json() as any;
    expect(j).toMatchObject({ id: 'salon', category: 'salon', language: 'bn', business_name: 'Glow Salon', name: 'সেলুন ও স্পা' });
    expect(j.followup_templates.hot).toContain('{business}');
  });

  it('honours ?lang and falls back to general / English', async () => {
    const hi = await (await call(BIZ, 'usr_pb', '919830055501', '?lang=hi')).json() as any;
    expect(hi.language).toBe('hi');
    expect(hi.qualifying_questions[0]).toBe(PLAYBOOKS.salon.qualifyingQuestions[0].hi);
    const gen = await (await call(BIZ_GEN, 'usr_pb_gen', '919830055502', '?lang=xx')).json() as any;
    expect(gen).toMatchObject({ id: 'general', category: 'other', language: 'en', business_name: 'Plain Shop' });
  });
});

describe('default WhatsApp draft after a call', () => {
  let seq = 0;
  async function seedCall(name: string): Promise<{ callId: string; leadId: string }> {
    const n = ++seq;
    const leadId = `lead_pb_${n}_${Date.now()}`;
    const callId = `call_pb_${n}_${Date.now()}`;
    await env.DB.batch([
      env.DB.prepare("INSERT INTO leads (id, business_id, name, phone, status) VALUES (?, ?, ?, ?, 'queued')").bind(leadId, BIZ, name, `9198300${String(n).padStart(5, '0')}`),
      env.DB.prepare("INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, status, started_at) VALUES (?, ?, ?, ?, 'x', 'calling', datetime('now'))").bind(callId, BIZ, leadId, name),
    ]);
    return { callId, leadId };
  }

  async function webhook(callId: string, output: Record<string, unknown>) {
    const token = await sarvamWebhookToken(WEBHOOK_SECRET, callId);
    return app.fetch(new Request(`http://localhost/webhooks/sarvam?call_id=${callId}&token=${token}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ status: 'completed', duration_seconds: 75, output_variables: output }),
    }), env);
  }

  const followup = (callId: string) => env.DB.prepare('SELECT message, status FROM followups WHERE call_id = ?').bind(callId).first<any>();
  const base = { lead_score: 60, intent: 'exploring', temperature: 'warm', summary: 's', next_action: 'send_whatsapp', whatsapp_followup_required: true };

  it('uses the playbook template in the employee language when the agent wrote none', async () => {
    const { callId } = await seedCall('Asha Rao');
    expect((await webhook(callId, base)).status).toBe(200);
    const fu = await followup(callId);
    expect(fu.status).toBe('ready');
    expect(fu.message).toBe(playbookFollowupMessage(PLAYBOOKS.salon, 'warm', 'bn', { name: 'Asha', business: 'Glow Salon' }));
  });

  it('follows the language the call was held in and the outcome', async () => {
    const { callId } = await seedCall('Ravi Kumar');
    await webhook(callId, { ...base, lead_score: 90, intent: 'interested', temperature: 'hot', language: 'Hindi' });
    expect((await followup(callId)).message).toBe('नमस्ते Ravi, Glow Salon में बुकिंग के लिए धन्यवाद! अपनी अपॉइंटमेंट कन्फ़र्म करने के लिए यहाँ जवाब दें, और समय बदलना हो तो बताएँ।');
  });

  it("keeps the agent's own message when it wrote one", async () => {
    const { callId } = await seedCall('Meera');
    await webhook(callId, { ...base, whatsapp_message: '  Custom note  ' });
    expect((await followup(callId)).message).toBe('Custom note');
  });

  it('drafts nothing by default for an opt-out', async () => {
    const { callId } = await seedCall('Opt Out');
    await webhook(callId, { ...base, intent: 'opt_out', temperature: 'cold' });
    expect(await followup(callId)).toBeNull();
  });

  it('defaultFollowupDraft falls back to the general playbook and English', async () => {
    const msg = await defaultFollowupDraft(env.DB, BIZ_GEN, { leadName: 'Sam Lee', temperature: 'cold' });
    expect(msg).toBe(playbookFollowupMessage(PLAYBOOKS.general, 'not_interested', 'en', { name: 'Sam', business: 'Plain Shop' }));
    const unknownBiz = await defaultFollowupDraft(env.DB, 'biz_missing', { callbackAt: 'x', language: 'Bengali' });
    expect(unknownBiz).toBe(playbookFollowupMessage(PLAYBOOKS.general, 'callback', 'bn', { name: null, business: null }));
  });
});
