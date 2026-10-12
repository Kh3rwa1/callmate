import { describe, it, expect, beforeAll } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import app from '../src/index';
import { signJWT } from '../src/auth';
import { buildDigest } from '../src/services/digest';
import { enquiryNoticeText, notifyOwner } from '../src/services/lead_capture';
import { asOwnerLang, ownerLanguage, ownerText } from '../src/services/owner_text';

describe('Owner notifications follow the app language', () => {
  const secret = 'test-jwt-signing-secret-key-32chars-min-length';
  const biz = 'biz_lang_1';
  const user = 'usr_lang_1';
  let token: string;

  beforeAll(async () => {
    await migrateTestDb();
    await env.DB.batch([
      env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name, category) VALUES (?, 'Sunrise Coaching', 'education')").bind(biz),
      env.DB.prepare('INSERT OR REPLACE INTO users (id, phone, business_id) VALUES (?, ?, ?)').bind(user, '919830000777', biz),
    ]);
    token = await signJWT({ sub: user, phone: '919830000777', business_id: biz, type: 'access' }, secret, 3600);
  });

  const patch = (body: unknown) => app.fetch(
    new Request('http://localhost/business', {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
      body: JSON.stringify(body),
    }),
    env,
  );

  it('new businesses default to English', async () => {
    expect(await ownerLanguage(env as any, biz)).toBe('en');
  });

  it('PATCH /business saves app_language and returns it', async () => {
    const res = await patch({ app_language: 'hi' });
    expect(res.status).toBe(200);
    expect(((await res.json()) as any).app_language).toBe('hi');
    expect(await ownerLanguage(env as any, biz)).toBe('hi');
  });

  it('rejects languages the app does not have', async () => {
    expect((await patch({ app_language: 'fr' })).status).toBe(400);
  });

  it('enquiry notification row is written in Hindi', async () => {
    await notifyOwner(env as any, biz, 'lead_x', 'Ravi Kumar', 'calling');
    const row = await env.DB.prepare(
      "SELECT title, body, action_label FROM notifications WHERE business_id = ? AND type = 'new_lead' ORDER BY created_at DESC LIMIT 1",
    ).bind(biz).first<any>();
    expect(row.title).toBe('Ravi की नई पूछताछ');
    expect(row.body).toBe('आपका AI कर्मचारी अभी उन्हें कॉल कर रहा है।');
    expect(row.action_label).toBe('देखें');
  });

  it('English copy is unchanged', () => {
    expect(enquiryNoticeText('calling', 'Ravi Kumar')).toEqual({
      title: 'New enquiry from Ravi', body: 'Your AI employee is calling them now.',
    });
  });

  it('digest speaks Hindi and Bengali', () => {
    const r = { enquiries: 2, calls: 12, calls_connected: 8, interested: 5, ready_to_buy: 3 } as any;
    expect(buildDigest(r, 1, 'hi')).toMatchObject({
      title: 'CallPilot के साथ आपका दिन',
      body: 'आज: 12 कॉल, 3 खरीदने को तैयार, कल 1 कॉल बैक — देखने के लिए टैप करें',
    });
    expect(buildDigest(r, 0, 'bn')!.title).toBe('CallPilot-এর সঙ্গে আপনার দিন');
  });

  it('hot lead copy in each language', () => {
    expect(ownerText('en').hotLeadBody('Rahul', 87)).toBe('Rahul is very interested (87/100)');
    expect(ownerText('hi').hotLeadTitle).toBe('खरीदने को तैयार ग्राहक');
    expect(ownerText('bn').hotLeadBody('Rahul', 87)).toContain('Rahul');
  });

  it('unknown stored values fall back to English', () => {
    expect(asOwnerLang('xx')).toBe('en');
    expect(asOwnerLang(null)).toBe('en');
  });
});
