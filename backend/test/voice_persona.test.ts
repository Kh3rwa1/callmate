import { describe, it, expect, beforeAll } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import app from '../src/index';
import { signJWT } from '../src/auth';
import { sarvamSpeaker, voiceGender, voiceLang } from '../src/services/voice_persona';

describe('voice persona', () => {
  it('reads the gender from every stored voice label', () => {
    expect(voiceGender('Warm · Female')).toBe('female');
    expect(voiceGender('Friendly Female (Hindi/English)')).toBe('female');
    expect(voiceGender('Friendly · Male')).toBe('male');
    expect(voiceGender('Confident · Male')).toBe('male');
    expect(voiceGender(undefined)).toBe('female');
    expect(voiceLang('hi')).toBe('hi');
    expect(voiceLang('fr')).toBe('en');
  });

  it('never uses the retired v1 voice "meera"', () => {
    for (const lang of ['en', 'hi', 'bn'] as const) {
      for (const g of ['female', 'male'] as const) {
        expect(sarvamSpeaker(g, lang)).not.toBe('meera');
      }
      expect(sarvamSpeaker('male', lang)).not.toBe(sarvamSpeaker('female', lang));
    }
  });
});

describe('/voice/test-session speaks in the employee\'s voice', () => {
  const secret = 'test-jwt-signing-secret-key-32chars-min-length';
  const otpPepper = 'test-otp-pepper-secret-32chars-min-length';
  const bizId = 'biz_voice_persona';
  const userId = 'usr_voice_persona';
  const phone = '919876543288';
  let token: string;

  const start = (body?: unknown) =>
    app.fetch(
      new Request('http://localhost/voice/test-session', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
        body: body === undefined ? undefined : JSON.stringify(body),
      }),
      { ...env, JWT_SIGNING_KEY: secret, OTP_PEPPER: otpPepper },
    );

  beforeAll(async () => {
    await migrateTestDb();
    await env.DB.batch([
      env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name, category) VALUES (?, 'Arjun Clinic', 'clinic')").bind(bizId),
      env.DB.prepare('INSERT OR REPLACE INTO users (id, phone, business_id) VALUES (?, ?, ?)').bind(userId, phone, bizId),
      env.DB.prepare("INSERT OR REPLACE INTO agents (id, business_id, name, role, voice) VALUES ('agt_voice_persona', ?, 'Arjun', 'Appointment Assistant', 'Friendly · Male')").bind(bizId),
    ]);
    token = await signJWT({ sub: userId, phone, business_id: bizId, type: 'access' }, secret, 3600);
  });

  it('a man employee gets a man\'s voice, in the language the app asks for', async () => {
    const res = await start({ lang: 'hi' });
    expect(res.status).toBe(200);
    const v = ((await res.json()) as any).agent_variables;
    expect(v.gender).toBe('male');
    expect(v.speaker).toBe('shubh_hi_customer');
    expect(v.language_code).toBe('hi-IN');
  });

  it('without a body it still works, in English', async () => {
    const res = await start();
    expect(res.status).toBe(200);
    const v = ((await res.json()) as any).agent_variables;
    expect(v.speaker).toBe('sunny_enhi_customer');
  });
});
