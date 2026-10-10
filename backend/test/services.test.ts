import { describe, it, expect, vi, beforeAll, afterAll } from 'vitest';
import { env } from 'cloudflare:test';
import { useIndianBusinessHours, useRealClock } from './clock';
import { migrateTestDb } from './setup-db';
import { safeJsonParse } from '../src/utils/json';
import { maskPhone, encryptAtRest, decryptAtRest } from '../src/utils/crypto_data';
import {
  MockSmsProvider,
  Msg91SmsProvider,
  GupshupSmsProvider,
  ExotelSmsProvider,
  getSmsProvider,
} from '../src/sms';
import {
  isWithinCallingHours,
  isOptOutRequest,
  checkCallCompliance,
} from '../src/services/compliance';
import {
  parseJsonBody,
  otpRequestSchema,
  registerSchema,
  loginSchema,
  refreshSchema,
  createLeadSchema,
  patchLeadSchema,
  importLeadsSchema,
  createCampaignSchema,
  deviceTokenSchema,
} from '../src/schemas/validation';

describe('Utility & Services Unit Tests', () => {
  const encKey = 'super-secret-key-at-least-32-characters-long';
  const bizId = 'biz_services_test';

  beforeAll(async () => {
    await migrateTestDb();
    await env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name) VALUES (?, 'Test Business')").bind(bizId).run();
  });

  describe('json utils', () => {
    it('safely parses valid and invalid JSON', () => {
      expect(safeJsonParse('{"a":1}', {})).toEqual({ a: 1 });
      expect(safeJsonParse('invalid-json', { fallback: true })).toEqual({ fallback: true });
      expect(safeJsonParse(null as any, [1, 2])).toEqual([1, 2]);
    });
  });

  describe('crypto_data utils', () => {
    it('masks phone numbers correctly according to compliance spec', () => {
      expect(maskPhone('919830012345')).toBe('91XXXXXX2345');
      expect(maskPhone('9830012345')).toBe('98XXXX2345');
      expect(maskPhone('123')).toBe('***');
    });

    it('encrypts and decrypts sensitive data at rest using AES-GCM', async () => {
      const plaintext = 'Secret caller transcript: caller confirmed budget is 500k';
      const encrypted = await encryptAtRest(plaintext, encKey);
      expect(encrypted).not.toBe(plaintext);
      expect(encrypted).toContain(':'); // iv:ciphertext format

      const decrypted = await decryptAtRest(encrypted, encKey);
      expect(decrypted).toBe(plaintext);
    });

    it('decryptAtRest returns original text if not encrypted format (legacy support)', async () => {
      const legacy = 'Plaintext unencrypted legacy transcript';
      const decrypted = await decryptAtRest(legacy, encKey);
      expect(decrypted).toBe(legacy);
    });

    it('encryptAtRest and decryptAtRest fail closed if secret is missing', async () => {
      await expect(encryptAtRest('test', '')).rejects.toThrow('Encryption key secret is required');
      await expect(decryptAtRest('enc:v1:abc:def', '')).rejects.toThrow('Decryption key secret is required');
    });
  });

  describe('SMS providers', () => {
    it('MockSmsProvider works in non-production environment', async () => {
      const mock = new MockSmsProvider('development');
      const sent = await mock.sendOtp('919830012345', '123456');
      expect(sent).toBe(true);
    });

    it('MockSmsProvider throws in production environment', async () => {
      const mock = new MockSmsProvider('production');
      await expect(mock.sendOtp('919830012345', '123456')).rejects.toThrow('Security violation');
    });

    it('getSmsProvider throws in production if no provider configured', () => {
      expect(() => getSmsProvider({ ENVIRONMENT: 'production' } as any)).toThrow('Production SMS provider is not configured');
    });

    it('getSmsProvider resolves configured providers', () => {
      const p1 = getSmsProvider({ MSG91_AUTH_KEY: 'k1' } as any);
      expect(p1).toBeInstanceOf(Msg91SmsProvider);

      const p2 = getSmsProvider({ GUPSHUP_API_KEY: 'k2' } as any);
      expect(p2).toBeInstanceOf(GupshupSmsProvider);

      const p3 = getSmsProvider({ EXOTEL_SID: 's3', EXOTEL_TOKEN: 't3' } as any);
      expect(p3).toBeInstanceOf(ExotelSmsProvider);
    });

    it('Live SMS providers handle mock fetch requests', async () => {
      const originalFetch = globalThis.fetch;
      globalThis.fetch = vi.fn().mockResolvedValue(new Response('ok', { status: 200 })) as any;

      const msg91 = new Msg91SmsProvider('test_key');
      expect(await msg91.sendOtp('919830012345', '123456')).toBe(true);

      const gupshup = new GupshupSmsProvider('test_key');
      expect(await gupshup.sendOtp('919830012345', '123456')).toBe(true);

      const exotel = new ExotelSmsProvider('sid', 'tok');
      expect(await exotel.sendOtp('919830012345', '123456')).toBe(true);

      globalThis.fetch = originalFetch;
    });
  });

  describe('Compliance service', () => {
    beforeAll(useIndianBusinessHours);
    afterAll(useRealClock);

    it('evaluates calling hours window correctly', () => {
      const inWindow = isWithinCallingHours(0, 24, 'Asia/Kolkata');
      expect(inWindow).toBe(true);
      const outsideWindow = isWithinCallingHours(25, 26, 'Asia/Kolkata');
      expect(outsideWindow).toBe(false);
    });

    it('detects opt-out phrases from caller transcript or output variables', () => {
      expect(isOptOutRequest({ transcript: [{ role: 'user', message: "stop calling me" }] })).toBe(true);
      expect(isOptOutRequest({ transcript: [{ role: 'user', message: "don't call me" }] })).toBe(true);
      expect(isOptOutRequest({ transcript: [{ role: 'user', message: "remove my number" }] })).toBe(true);
      expect(isOptOutRequest({ output_variables: { intent: 'opt_out' } })).toBe(true);
      expect(isOptOutRequest({ transcript: [{ role: 'user', message: "Hello, tell me about the fees" }] })).toBe(false);
    });

    it('evaluates lead compliance: DNC, calling hours, attempt limits', async () => {
      const leadDncId = 'lead_dnc_test';
      const leadOkId = 'lead_ok_test';

      await env.DB.batch([
        env.DB.prepare("INSERT OR REPLACE INTO leads (id, business_id, name, phone, do_not_call, consent) VALUES (?, ?, 'DNC Lead', '919830011111', 1, 'opt_out')").bind(leadDncId, bizId),
        env.DB.prepare("INSERT OR REPLACE INTO leads (id, business_id, name, phone, do_not_call, consent) VALUES (?, ?, 'OK Lead', '919830022222', 0, 'inquiry')").bind(leadOkId, bizId),
      ]);

      // 1. DNC lead check
      const dncResult = await checkCallCompliance(env.DB, {
        businessId: bizId,
        leadId: leadDncId,
        hoursStart: 0,
        hoursEnd: 24,
      });
      expect(dncResult.allowed).toBe(false);
      expect(dncResult.reason).toBe('do_not_call');

      // 2. Allowed when within window and not DNC
      const okResult = await checkCallCompliance(env.DB, {
        businessId: bizId,
        leadId: leadOkId,
        hoursStart: 0,
        hoursEnd: 24,
      });
      expect(okResult.allowed).toBe(true);

      // 3. Rescheduled when outside calling hours
      const outsideResult = await checkCallCompliance(env.DB, {
        businessId: bizId,
        leadId: leadOkId,
        hoursStart: 25, // impossible window to simulate outside hours
        hoursEnd: 26,
      });
      expect(outsideResult.allowed).toBe(false);
      expect(outsideResult.reason).toBe('outside_hours');
      expect(outsideResult.reschedule).toBe(true);
    });
  });

  describe('Validation schemas', () => {
    it('validates request bodies with zod schemas', async () => {
      const validReq: any = { req: { json: async () => ({ phone: '9830012345' }) } };
      const parsed = await parseJsonBody(validReq, otpRequestSchema);
      expect(parsed.success).toBe(true);

      const invalidReq: any = {
        req: { json: async () => ({}) },
        json: (data: any, status: number) => ({ data, status }),
      };
      const invalidParsed = await parseJsonBody(invalidReq, otpRequestSchema);
      expect(invalidParsed.success).toBe(false);
    });

    it('validates schemas for createLead, createCampaign, importLeads', () => {
      expect(createLeadSchema.safeParse({ name: 'Rahul', phone: '9830012345' }).success).toBe(true);
      expect(createLeadSchema.safeParse({ name: 'R' }).success).toBe(false); // phone missing

      expect(createCampaignSchema.safeParse({ purpose: 'Admission Follow-ups', lead_ids: ['l1', 'l2'] }).success).toBe(true);

      expect(importLeadsSchema.safeParse({ leads: [{ name: 'A', phone: '9830012345' }] }).success).toBe(true);
      expect(importLeadsSchema.safeParse({ leads: [] }).success).toBe(false);
      expect(deviceTokenSchema.safeParse({ token: 'tok_123', platform: 'android' }).success).toBe(true);
    });

    it('masks phone numbers and outputs structured JSON logs', async () => {
      const { maskPhone, logInfo, logWarn, logError } = await import('../src/utils/logger');

      expect(maskPhone('+919830012345')).toBe('91XXXXXXX345');
      expect(maskPhone('9830012345')).toBe('98XXXXX345');
      expect(maskPhone('123')).toBe('XXXXX');
      expect(maskPhone('')).toBe('');

      // Test structured logging methods
      logInfo('Test info log', { test: true });
      logWarn('Test warn log', { test: true });
      logError('Test error log', new Error('Something failed'), { requestId: 'req_123' });
      logError('Test raw error log', 'raw_err_string');
    });
  });
});
