import { describe, it, expect, beforeAll } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import app from '../src/index';
import { randomToken } from '../src/services/lead_capture';
import { formPage, thankYouPage, messagePage, consentText, FORM_CSP } from '../src/routes/lead_capture_public';
import { stopPage } from '../src/routes/stop';
import { legalVars, privacyPage, escapeHtml } from '../src/routes/legal';
import {
  parseAcceptLanguage,
  parseLangParam,
  businessPageLang,
  resolvePageLang,
  languageSwitcher,
  withLang,
  isPageLang,
} from '../src/services/page_lang';
import { FORM_STRINGS, STOP_STRINGS } from '../src/services/public_page_strings';
import { formConsentTextVersion, CONSENT_TEXT_VERSIONS } from '../src/services/consent';

const BIZ_EN = 'biz_l10n_en';
const BIZ_HI = 'biz_l10n_hi';
const BIZ_BN = 'biz_l10n_bn';
const BIZ_NONE = 'biz_l10n_none';
const LANGS = ['en', 'hi', 'bn'] as const;

let ipSeq = 0;
const ip = () => `10.77.${Math.floor(++ipSeq / 250)}.${ipSeq % 250}`;
const queueEnv = { ...env, CAMPAIGN_QUEUE: { send: async () => {}, sendBatch: async () => {} } } as any;

async function seedForm(businessId: string): Promise<string> {
  const slug = randomToken(12);
  await env.DB.prepare('INSERT INTO lead_sources (id, business_id, kind, public_slug, auto_call) VALUES (?, ?, ?, ?, 1)')
    .bind(`lsrc_l10n_${slug}`, businessId, 'form', slug).run();
  return slug;
}

const get = (path: string, headers: Record<string, string> = {}) =>
  app.fetch(new Request(`http://localhost${path}`, { headers }), env);

const post = (path: string, fields: Record<string, string>, headers: Record<string, string> = {}) =>
  app.fetch(new Request(`http://localhost${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'cf-connecting-ip': ip(), ...headers },
    body: new URLSearchParams(fields).toString(),
  }), queueEnv);

beforeAll(async () => {
  await migrateTestDb();
  const biz = (id: string, name: string) => env.DB.prepare('INSERT OR REPLACE INTO businesses (id, name, category) VALUES (?, ?, ?)').bind(id, name, 'coaching');
  const agent = (id: string, businessId: string, languages: string) => env.DB.prepare(
    "INSERT OR REPLACE INTO agents (id, business_id, name, role, status, languages, calling_hours_start, calling_hours_end) VALUES (?, ?, 'Maya', 'Counselor', 'active', ?, 0, 24)"
  ).bind(id, businessId, languages);
  await env.DB.batch([
    biz(BIZ_EN, 'English <Academy>'),
    agent('agt_l10n_en', BIZ_EN, '["English","Hindi"]'),
    biz(BIZ_HI, 'Sharma "Classes" & Co'),
    agent('agt_l10n_hi', BIZ_HI, '["Hindi","English"]'),
    biz(BIZ_BN, 'Kolkata Coaching'),
    agent('agt_l10n_bn', BIZ_BN, '["Bengali"]'),
    biz(BIZ_NONE, 'Tamil Tutors'),
    agent('agt_l10n_none', BIZ_NONE, '["Tamil"]'),
  ]);
});

describe('page language selection', () => {
  it('parses ?lang strictly', () => {
    expect(parseLangParam('hi')).toBe('hi');
    expect(parseLangParam(' BN ')).toBe('bn');
    expect(parseLangParam('fr')).toBeNull();
    expect(parseLangParam(undefined)).toBeNull();
    expect(isPageLang('en')).toBe(true);
    expect(isPageLang(3)).toBe(false);
  });

  it('reads Accept-Language by q-value and region-less base', () => {
    expect(parseAcceptLanguage('bn-IN,bn;q=0.9,en;q=0.8')).toBe('bn');
    expect(parseAcceptLanguage('en;q=0.5, hi-IN;q=0.9')).toBe('hi');
    expect(parseAcceptLanguage('fr-FR, de;q=0.8, hi;q=0.1')).toBe('hi');
    expect(parseAcceptLanguage('ta-IN,fr')).toBeNull();
    expect(parseAcceptLanguage('hi;q=0, en;q=bad')).toBeNull();
    expect(parseAcceptLanguage('')).toBeNull();
    expect(parseAcceptLanguage(null)).toBeNull();
  });

  it('takes the business default from the employee first language', () => {
    expect(businessPageLang('["Hindi","English"]')).toBe('hi');
    expect(businessPageLang('["Bangla"]')).toBe('bn');
    expect(businessPageLang(['বাংলা'])).toBe('bn');
    expect(businessPageLang(['हिन्दी'])).toBe('hi');
    expect(businessPageLang('["English"]')).toBe('en');
    expect(businessPageLang('Hindi')).toBe('hi');
    expect(businessPageLang('["Tamil"]')).toBeNull();
    expect(businessPageLang(null)).toBeNull();
    expect(businessPageLang('[]')).toBeNull();
  });

  it('prefers ?lang, then the business default, then Accept-Language, then English', () => {
    expect(resolvePageLang({ query: 'bn', businessDefault: 'hi', acceptLanguage: 'en' })).toBe('bn');
    expect(resolvePageLang({ query: 'xx', businessDefault: 'hi', acceptLanguage: 'bn' })).toBe('hi');
    expect(resolvePageLang({ businessDefault: null, acceptLanguage: 'bn-IN' })).toBe('bn');
    expect(resolvePageLang({})).toBe('en');
  });

  it('builds plain switcher links with the current language unlinked', () => {
    expect(withLang('/stop', 'hi')).toBe('/stop?lang=hi');
    expect(withLang('/x?a=1', 'bn')).toBe('/x?a=1&lang=bn');
    const nav = languageSwitcher('/f/abc', 'hi', 'भाषा');
    expect(nav).toContain('aria-label="भाषा"');
    expect(nav).toContain('<a href="/f/abc?lang=en" hreflang="en" lang="en">English</a>');
    expect(nav).toContain('<strong lang="hi" aria-current="true">हिन्दी</strong>');
    expect(nav).toContain('<a href="/f/abc?lang=bn" hreflang="bn" lang="bn">বাংলা</a>');
    expect(nav).not.toContain('href="/f/abc?lang=hi"');
  });
});

describe('hosted enquiry form in English, Hindi and Bengali', () => {
  it('renders each language with <html lang>, native text and escaping intact', () => {
    for (const lang of LANGS) {
      const t = FORM_STRINGS[lang];
      const html = formPage('A&B <Co>', 'abcdefghijkl', { name: '"><script>x</script>' }, '<b>err</b>', undefined, lang);
      expect(html).toContain(`<html lang="${lang}">`);
      expect(html).toContain(t.submit);
      expect(html).toContain(t.nameLabel);
      expect(html).toContain(t.lede);
      expect(html).toContain(`action="/f/abcdefghijkl?lang=${lang}"`);
      expect(html).toContain('A&amp;B &lt;Co&gt;');
      expect(html).not.toContain('<Co>');
      expect(html).not.toMatch(/<script/i);
      expect(html).toContain('&lt;b&gt;err&lt;/b&gt;');
      // Consent sentence names the business (escaped) in the page language.
      expect(html).toContain(escapeHtml(consentText('A&B <Co>', lang)));
    }
    expect(formPage('B', 'abcdefghijkl', {}, undefined, undefined, 'hi')).toContain('स्वचालित AI कॉल');
    expect(formPage('B', 'abcdefghijkl', {}, undefined, undefined, 'bn')).toContain('স্বয়ংক্রিয় AI কল');
    // Default stays English.
    expect(formPage('B', 'abcdefghijkl')).toContain('<html lang="en">');
  });

  it('keeps the consent meaning in every language: the business, the call, the enquiry, maybe AI', () => {
    expect(consentText('Biz')).toBe('I agree to receive a call from Biz about my enquiry (may be an automated AI call).');
    for (const lang of LANGS) {
      const s = consentText('Biz', lang);
      expect(s).toContain('Biz');
      expect(s).toContain('AI');
    }
    expect(formConsentTextVersion('en')).toBe(CONSENT_TEXT_VERSIONS.form);
    expect(formConsentTextVersion('hi')).toBe('enquiry-form-2026-10-hi');
    expect(formConsentTextVersion('bn')).toBe('enquiry-form-2026-10-bn');
  });

  it('thank-you and message pages are localized and escaped', () => {
    expect(thankYouPage('X<y>', 'Ravi Kumar', true, undefined, 'hi')).toContain('धन्यवाद, Ravi!');
    expect(thankYouPage('X<y>', 'Ravi Kumar', true, undefined, 'hi')).toContain('X&lt;y&gt; आपको लगभग एक मिनट में कॉल करेगा');
    expect(thankYouPage('X', '', false, undefined, 'bn')).toContain('<h1>ধন্যবাদ!</h1>');
    expect(thankYouPage('X', '', false, undefined, 'bn')).toContain('শীঘ্রই আপনার সঙ্গে যোগাযোগ করবে');
    expect(thankYouPage('X', '<i>A</i>', false)).toContain('Thank you, &lt;i&gt;A&lt;/i&gt;!');
    const msg = messagePage('<T>', '<M>', 'bn', '/f/abcdefghijkl');
    expect(msg).toContain('<html lang="bn">');
    expect(msg).toContain('&lt;T&gt;');
    expect(msg).toContain('href="/f/abcdefghijkl?lang=en"');
    expect(messagePage('T', 'M')).not.toContain('class="langs"');
  });

  it('GET defaults to the employee first language, ?lang overrides, Accept-Language only without a business default', async () => {
    const hi = await seedForm(BIZ_HI);
    const res = await get(`/f/${hi}`, { 'accept-language': 'bn' });
    expect(res.status).toBe(200);
    expect(res.headers.get('Content-Language')).toBe('hi');
    expect(res.headers.get('Content-Security-Policy')).toBe(FORM_CSP);
    const html = await res.text();
    expect(html).toContain('<html lang="hi">');
    expect(html).toContain('Sharma &quot;Classes&quot; &amp; Co');
    expect(html).toContain(`href="/f/${hi}?lang=bn"`);
    expect(html).not.toMatch(/<script/i);

    expect(await (await get(`/f/${hi}?lang=bn`)).text()).toContain('<html lang="bn">');
    expect(await (await get(`/f/${hi}?lang=en`, { 'accept-language': 'hi' })).text()).toContain('<html lang="en">');
    expect(await (await get(`/f/${hi}?lang=zz`)).text()).toContain('<html lang="hi">');

    const bn = await seedForm(BIZ_BN);
    expect(await (await get(`/f/${bn}`)).text()).toContain('কল করার অনুরোধ করুন');

    // English employee: English, even if the browser prefers Hindi.
    const en = await seedForm(BIZ_EN);
    expect(await (await get(`/f/${en}`, { 'accept-language': 'hi' })).text()).toContain('<html lang="en">');

    // No usable default (Tamil): the browser decides, else English.
    const none = await seedForm(BIZ_NONE);
    expect(await (await get(`/f/${none}`, { 'accept-language': 'bn-IN,en;q=0.5' })).text()).toContain('<html lang="bn">');
    expect(await (await get(`/f/${none}`)).text()).toContain('<html lang="en">');
  });

  it('not-found page follows ?lang and Accept-Language, with switcher links only for well-formed slugs', async () => {
    const res = await get('/f/nosuchslug999', { 'accept-language': 'hi-IN' });
    expect(res.status).toBe(404);
    const html = await res.text();
    expect(html).toContain('<html lang="hi">');
    expect(html).toContain(FORM_STRINGS.hi.notFoundTitle);
    expect(html).toContain('href="/f/nosuchslug999?lang=bn"');
    const bad = await get('/f/bad-slug!?lang=bn');
    expect(bad.status).toBe(404);
    const badHtml = await bad.text();
    expect(badHtml).toContain(FORM_STRINGS.bn.notFoundMessage);
    expect(badHtml).not.toContain('class="langs"');
  });

  it('validation errors come back in the page language', async () => {
    const slug = await seedForm(BIZ_BN);
    const noName = await post(`/f/${slug}?lang=hi`, { name: '', phone: '9830012345', consent: 'yes' });
    expect(noName.status).toBe(400);
    expect(await noName.text()).toContain(FORM_STRINGS.hi.errName);
    const badPhone = await post(`/f/${slug}`, { name: 'Ravi', phone: '12', consent: 'yes' });
    expect(await badPhone.text()).toContain(FORM_STRINGS.bn.errPhone);
    const noConsent = await post(`/f/${slug}?lang=en`, { name: 'Ravi', phone: '9830012345' });
    expect(await noConsent.text()).toContain(FORM_STRINGS.en.errConsent);
    const tooLong = await app.fetch(new Request(`http://localhost/f/${slug}`, {
      method: 'POST', headers: { 'content-length': '99999', 'cf-connecting-ip': ip() }, body: 'x',
    }), queueEnv);
    expect(tooLong.status).toBe(413);
    expect(await tooLong.text()).toContain(FORM_STRINGS.bn.tooLongTitle);
  });

  it('records the consent event with the language-specific wording version', async () => {
    const slug = await seedForm(BIZ_HI);
    const cases = [
      { path: `/f/${slug}`, phone: '+91 98111 70001', version: 'enquiry-form-2026-10-hi', text: 'धन्यवाद, Asha!' },
      { path: `/f/${slug}?lang=bn`, phone: '+91 98111 70002', version: 'enquiry-form-2026-10-bn', text: 'ধন্যবাদ, Asha!' },
      { path: `/f/${slug}?lang=en`, phone: '+91 98111 70003', version: 'enquiry-form-2026-10', text: 'Thank you, Asha!' },
    ];
    for (const k of cases) {
      const res = await post(k.path, { name: 'Asha Rao', phone: k.phone, consent: 'yes' });
      expect(res.status).toBe(200);
      expect(await res.text()).toContain(k.text);
      const lead = await env.DB.prepare('SELECT id FROM leads WHERE business_id = ? AND phone = ?')
        .bind(BIZ_HI, k.phone.replace(/\D/g, '')).first<any>();
      const ev = await env.DB.prepare('SELECT source, text_version FROM consent_events WHERE lead_id = ?').bind(lead.id).first<any>();
      expect(ev).toEqual({ source: 'form', text_version: k.version });
    }
  });

  it('honeypot submissions get the localized thank-you page and create nothing', async () => {
    const slug = await seedForm(BIZ_BN);
    const res = await post(`/f/${slug}`, { name: 'Bot', phone: '9830077777', consent: 'yes', company_website: 'spam' });
    expect(res.status).toBe(200);
    expect(await res.text()).toContain('ধন্যবাদ, Bot!');
    expect(await env.DB.prepare('SELECT id FROM leads WHERE phone = ?').bind('919830077777').first()).toBeNull();
  });
});

describe('/stop in English, Hindi and Bengali', () => {
  const v = () => legalVars(env as any);

  it('renders every state in each language with <html lang> and switcher', () => {
    for (const lang of LANGS) {
      const t = STOP_STRINGS[lang];
      const form = stopPage(v(), { kind: 'form', error: '<x>', value: '"><b>' }, lang);
      expect(form).toContain(`<html lang="${lang}">`);
      expect(form).toContain(`<h1>${t.heading}</h1>`);
      expect(form).toContain(`action="/stop?lang=${lang}"`);
      expect(form).toContain('&lt;x&gt;');
      expect(form).toContain('&quot;&gt;&lt;b&gt;');
      expect(form).not.toMatch(/<script/i);
      expect(form).toContain('class="langs"');
      expect(form).toContain('1909');
      expect(stopPage(v(), { kind: 'done' }, lang)).toContain('role="status"');
      expect(stopPage(v(), { kind: 'limited' }, lang)).toContain('mailto:');
      expect(stopPage(v(), { kind: 'unavailable' }, lang)).toContain('mailto:');
    }
    expect(stopPage(v(), { kind: 'form' }, 'hi')).toContain('गोपनीयता नीति');
    expect(stopPage(v(), { kind: 'form' }, 'hi')).toContain('href="/stop?lang=hi">मेरे नंबर पर कॉल बंद करें</a>');
    expect(stopPage(v(), { kind: 'form' }, 'bn')).toContain('কোনো প্রশ্ন আছে?');
    // Legal pages themselves stay English.
    expect(privacyPage(v())).toContain('<html lang="en">');
  });

  it('GET picks ?lang, then Accept-Language, then English', async () => {
    const bn = await get('/stop', { 'accept-language': 'bn-IN,bn;q=0.9' });
    expect(bn.headers.get('Content-Language')).toBe('bn');
    expect(await bn.text()).toContain('<html lang="bn">');
    expect(await (await get('/stop?lang=hi', { 'accept-language': 'bn' })).text()).toContain('<html lang="hi">');
    expect(await (await get('/stop')).text()).toContain('<html lang="en">');
  });

  it('POST errors and confirmation are localized', async () => {
    const bad = await post('/stop?lang=hi', { phone: '12' });
    expect(bad.status).toBe(400);
    expect(await bad.text()).toContain(STOP_STRINGS.hi.errPhone);
    const ok = await post('/stop?lang=bn', { phone: '98765 07001' });
    expect(ok.status).toBe(200);
    expect(await ok.text()).toContain('হয়ে গেছে।');
  });
});
