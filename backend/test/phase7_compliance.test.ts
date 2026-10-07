import { describe, it, expect, beforeAll } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import app from '../src/index';
import { signJWT } from '../src/auth';
import { isOptOutRequest, normalizeTranscript } from '../src/services/compliance';

describe('Phase 7: Compliance, Opt-Out Detection, Consent Defaults & Attestation', () => {
  const secret = 'test-jwt-signing-secret-key-32chars-min-length';
  const otpPepper = 'test-otp-pepper-secret-32chars-min-length';
  const bizId = 'biz_p7_test';
  const userId = 'usr_p7_test';
  const phone = '919876543222';
  let token: string;

  beforeAll(async () => {
    await migrateTestDb();

    await env.DB.batch([
      env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name, category) VALUES (?, 'Apex Academy', 'coaching')").bind(bizId),
      env.DB.prepare("INSERT OR REPLACE INTO users (id, phone, business_id) VALUES (?, ?, ?)").bind(userId, phone, bizId),
      env.DB.prepare("INSERT OR REPLACE INTO agents (id, business_id, name, role, status) VALUES ('agent_p7', ?, 'Maya', 'Counselor', 'active')").bind(bizId),
      env.DB.prepare("INSERT OR REPLACE INTO usage (id, business_id, plan_name, included_minutes, renews_at, price_inr, minutes_used, calls_made, rate_per_minute_inr) VALUES ('usg_p7', ?, 'Founding', 1000, datetime('now', '+30 days'), 4999, 0, 0, 6)").bind(bizId),
    ]);

    token = await signJWT({ sub: userId, phone, business_id: bizId, type: 'access' }, secret, 3600);
  });

  describe('Part 1: Multi-Lingual Opt-Out Pattern Matching & False Positive Guard', () => {
    it('normalizes transcripts stripping punctuation and non-alphanumeric noise', () => {
      const input = "  Hello! Don't call me again... please?  ";
      const norm = normalizeTranscript(input);
      expect(norm).toBe("hello don't call me again please");
    });

    it('detects English opt-out phrases', () => {
      expect(isOptOutRequest({ transcript: [{ role: 'user', text: "stop calling" }] })).toBe(true);
      expect(isOptOutRequest({ transcript: [{ role: 'customer', text: "Please do not call me again" }] })).toBe(true);
      expect(isOptOutRequest({ transcript: [{ speaker: 'user', text: "remove my number from your database" }] })).toBe(true);
      expect(isOptOutRequest({ transcript: [{ role: 'user', text: "take this number off" }] })).toBe(true);
      expect(isOptOutRequest({ transcript: [{ role: 'user', text: "remove me from the list" }] })).toBe(true);
      expect(isOptOutRequest({ transcript: [{ role: 'user', text: "report you as spam" }] })).toBe(true);
    });

    it('detects Hinglish romanised opt-out phrases', () => {
      expect(isOptOutRequest({ transcript: [{ role: 'user', text: "bhai call mat karo" }] })).toBe(true);
      expect(isOptOutRequest({ transcript: [{ role: 'user', text: "dobara call mat karna" }] })).toBe(true);
      expect(isOptOutRequest({ transcript: [{ role: 'user', text: "mujhe phone mat kijiye" }] })).toBe(true);
      expect(isOptOutRequest({ transcript: [{ role: 'user', text: "mera number hata do" }] })).toBe(true);
      expect(isOptOutRequest({ transcript: [{ role: 'user', text: "band karo calling" }] })).toBe(true);
    });

    it('detects Hindi Devanagari opt-out phrases', () => {
      expect(isOptOutRequest({ transcript: [{ role: 'user', text: "कृपया कॉल मत करो" }] })).toBe(true);
      expect(isOptOutRequest({ transcript: [{ role: 'user', text: "दोबारा फोन मत करना" }] })).toBe(true);
      expect(isOptOutRequest({ transcript: [{ role: 'user', text: "मेरा नंबर हटा दो" }] })).toBe(true);
    });

    it('prevents agent disclaimer from triggering false positive opt-out', () => {
      const payloadWithAgentDisclaimer = {
        transcript: [
          { role: 'assistant', text: "You can say stop calling anytime if you wish to opt out." },
          { role: 'user', text: "Understood, tell me more about the fee structure for Class 11." }
        ]
      };
      expect(isOptOutRequest(payloadWithAgentDisclaimer)).toBe(false);
    });

    it('identifies opt-out from output_variables or next_action', () => {
      expect(isOptOutRequest({ output_variables: { intent: 'opt_out' } })).toBe(true);
      expect(isOptOutRequest({ output_variables: { next_action: 'do_not_call' } })).toBe(true);
      expect(isOptOutRequest({ next_action: 'dnc' })).toBe(true);
      expect(isOptOutRequest({ intent: 'interested' })).toBe(false);
    });
  });

  describe('Part 2: Consent Defaults on Lead Creation and Import', () => {
    it('defaults consent to unknown on lead creation when omitted', async () => {
      const res = await app.fetch(
        new Request('http://localhost/leads', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${token}`,
          },
          body: JSON.stringify({
            name: 'Rohit Sharma',
            phone: '919876500001',
          }),
        }),
        { ...env, JWT_SIGNING_KEY: secret, OTP_PEPPER: otpPepper }
      );

      expect(res.status).toBe(200);
      const data: any = await res.json();
      expect(data.consent).toBe('unknown');
    });

    it('defaults consent to unknown on bulk lead import when omitted', async () => {
      const res = await app.fetch(
        new Request('http://localhost/leads/import', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${token}`,
          },
          body: JSON.stringify({
            leads: [
              { name: 'Virat K', phone: '919876500002' },
              { name: 'Hardik P', phone: '919876500003', consent: 'explicit_opt_in' },
            ],
          }),
        }),
        { ...env, JWT_SIGNING_KEY: secret, OTP_PEPPER: otpPepper }
      );

      expect(res.status).toBe(200);
      const check1 = await env.DB.prepare("SELECT consent FROM leads WHERE phone = '919876500002'").first<any>();
      expect(check1.consent).toBe('unknown');

      const check2 = await env.DB.prepare("SELECT consent FROM leads WHERE phone = '919876500003'").first<any>();
      expect(check2.consent).toBe('explicit_opt_in');
    });
  });

  describe('Part 3: Campaign Start Consent Filtering & Attestation', () => {
    it('skips leads with unknown or opt_out consent when starting without attestation', async () => {
      // 1. Create 3 leads with different consent
      const l1Id = `ld_${crypto.randomUUID().slice(0, 8)}`;
      const l2Id = `ld_${crypto.randomUUID().slice(0, 8)}`;
      const l3Id = `ld_${crypto.randomUUID().slice(0, 8)}`;

      await env.DB.batch([
        env.DB.prepare("INSERT INTO leads (id, business_id, name, phone, consent, do_not_call) VALUES (?, ?, 'Lead 1', '919876500011', 'explicit_opt_in', 0)").bind(l1Id, bizId),
        env.DB.prepare("INSERT INTO leads (id, business_id, name, phone, consent, do_not_call) VALUES (?, ?, 'Lead 2', '919876500012', 'unknown', 0)").bind(l2Id, bizId),
        env.DB.prepare("INSERT INTO leads (id, business_id, name, phone, consent, do_not_call) VALUES (?, ?, 'Lead 3', '919876500013', 'opt_out', 0)").bind(l3Id, bizId),
      ]);

      // 2. Create campaign
      const campId = `cmp_${crypto.randomUUID().slice(0, 8)}`;
      await env.DB.batch([
        env.DB.prepare("INSERT INTO campaigns (id, business_id, purpose, status, total_leads) VALUES (?, ?, 'Admissions', 'draft', 3)").bind(campId, bizId),
        env.DB.prepare("INSERT INTO campaign_leads (campaign_id, lead_id, status) VALUES (?, ?, 'pending')").bind(campId, l1Id),
        env.DB.prepare("INSERT INTO campaign_leads (campaign_id, lead_id, status) VALUES (?, ?, 'pending')").bind(campId, l2Id),
        env.DB.prepare("INSERT INTO campaign_leads (campaign_id, lead_id, status) VALUES (?, ?, 'pending')").bind(campId, l3Id),
      ]);

      // 3. Start campaign without consent_attestation
      const res = await app.fetch(
        new Request(`http://localhost/campaigns/${campId}/start`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${token}`,
          },
          body: JSON.stringify({}),
        }),
        { ...env, JWT_SIGNING_KEY: secret, OTP_PEPPER: otpPepper }
      );

      expect(res.status).toBe(200);

      // l1 (explicit_opt_in) should be queued
      const cl1 = await env.DB.prepare("SELECT status FROM campaign_leads WHERE campaign_id = ? AND lead_id = ?").bind(campId, l1Id).first<any>();
      expect(cl1.status).toBe('queued');

      // l2 (unknown) should be skipped (skipped_no_consent)
      const cl2 = await env.DB.prepare("SELECT status FROM campaign_leads WHERE campaign_id = ? AND lead_id = ?").bind(campId, l2Id).first<any>();
      expect(cl2.status).toBe('skipped_no_consent');

      // l3 (opt_out) should be skipped (skipped_dnc)
      const cl3 = await env.DB.prepare("SELECT status FROM campaign_leads WHERE campaign_id = ? AND lead_id = ?").bind(campId, l3Id).first<any>();
      expect(cl3.status).toBe('skipped_dnc');
    });

    it('includes unknown consent leads when consent_attestation is true and records attestation', async () => {
      const lUnknownId = `ld_${crypto.randomUUID().slice(0, 8)}`;
      const lOptOutId = `ld_${crypto.randomUUID().slice(0, 8)}`;

      await env.DB.batch([
        env.DB.prepare("INSERT INTO leads (id, business_id, name, phone, consent, do_not_call) VALUES (?, ?, 'Lead Unk', '919876500021', 'unknown', 0)").bind(lUnknownId, bizId),
        env.DB.prepare("INSERT INTO leads (id, business_id, name, phone, consent, do_not_call) VALUES (?, ?, 'Lead Opt', '919876500022', 'opt_out', 0)").bind(lOptOutId, bizId),
      ]);

      const campId = `cmp_${crypto.randomUUID().slice(0, 8)}`;
      await env.DB.batch([
        env.DB.prepare("INSERT INTO campaigns (id, business_id, purpose, status, total_leads) VALUES (?, ?, 'Admissions', 'draft', 2)").bind(campId, bizId),
        env.DB.prepare("INSERT INTO campaign_leads (campaign_id, lead_id, status) VALUES (?, ?, 'pending')").bind(campId, lUnknownId),
        env.DB.prepare("INSERT INTO campaign_leads (campaign_id, lead_id, status) VALUES (?, ?, 'pending')").bind(campId, lOptOutId),
      ]);

      const res = await app.fetch(
        new Request(`http://localhost/campaigns/${campId}/start`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${token}`,
          },
          body: JSON.stringify({ consent_attestation: true }),
        }),
        { ...env, JWT_SIGNING_KEY: secret, OTP_PEPPER: otpPepper }
      );

      expect(res.status).toBe(200);

      // With attestation, unknown consent lead IS queued!
      const clUnk = await env.DB.prepare("SELECT status FROM campaign_leads WHERE campaign_id = ? AND lead_id = ?").bind(campId, lUnknownId).first<any>();
      expect(clUnk.status).toBe('queued');

      // opt_out lead is STILL skipped!
      const clOpt = await env.DB.prepare("SELECT status FROM campaign_leads WHERE campaign_id = ? AND lead_id = ?").bind(campId, lOptOutId).first<any>();
      expect(clOpt.status).toBe('skipped_dnc');

      // Verify campaign has attested_by and attested_at
      const camp = await env.DB.prepare("SELECT attested_by, attested_at FROM campaigns WHERE id = ?").bind(campId).first<any>();
      expect(camp.attested_by).toBe(userId);
      expect(camp.attested_at).toBeDefined();
    });
  });

  describe('Part 4: AI Disclosure Greeting', () => {
    it('/voice/test-session contains standard AI disclosure greeting', async () => {
      const res = await app.fetch(
        new Request('http://localhost/voice/test-session', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${token}`,
          },
        }),
        { ...env, JWT_SIGNING_KEY: secret, OTP_PEPPER: otpPepper }
      );

      expect(res.status).toBe(200);
      const data: any = await res.json();
      expect(data.greeting_text).toBe("Hello, I'm Maya, an AI assistant from Apex Academy. How can I assist you today?");
    });
  });
});
