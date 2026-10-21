// Words the owner reads in notifications and pushes, in the language they use the app in
// (businesses.app_language). English strings are the originals; keep meaning, not word order,
// when editing the others. Plain everyday words: owners are not technical.

import type { Env } from '../types';

export type OwnerLang = 'en' | 'hi' | 'bn';

export function asOwnerLang(v: unknown): OwnerLang {
  return v === 'hi' || v === 'bn' ? v : 'en';
}

/** The owner's app language; English when unknown or the column is missing. */
export async function ownerLanguage(env: Env, businessId: string): Promise<OwnerLang> {
  try {
    const row = await env.DB.prepare('SELECT app_language FROM businesses WHERE id = ?')
      .bind(businessId).first<{ app_language?: string }>();
    return asOwnerLang(row?.app_language);
  } catch {
    return 'en';
  }
}

const pick = <T>(lang: OwnerLang, en: T, hi: T, bn: T): T => (lang === 'hi' ? hi : lang === 'bn' ? bn : en);

export type EnquiryNotice =
  | 'calling' | 'scheduled' | 'manual' | 'not_called_dnc' | 'not_called_minutes' | 'not_called_failed';

export const ownerText = (lang: OwnerLang) => ({
  hotLeadTitle: pick(lang, 'Hot Lead Alert', 'खरीदने को तैयार ग्राहक', 'কিনতে আগ্রহী গ্রাহক'),
  hotLeadBody: (name: string, score: number) => pick(lang,
    `${name} is very interested (${score}/100)`,
    `${name} खरीदने में बहुत रुचि रखते हैं (${score}/100)`,
    `${name} কিনতে খুব আগ্রহী (${score}/100)`),
  viewResult: pick(lang, 'View Result', 'नतीजा देखें', 'ফলাফল দেখুন'),

  callbackTitle: pick(lang, 'Callback Scheduled', 'कॉल बैक तय हुआ', 'কল ব্যাক ঠিক হয়েছে'),
  callbackBody: (name: string) => pick(lang,
    `Callback scheduled with ${name}`,
    `${name} को कॉल बैक तय हुआ`,
    `${name}-কে কল ব্যাক ঠিক হয়েছে`),

  followUpTitle: pick(lang, 'Follow-up Ready', 'मैसेज तैयार है', 'মেসেজ তৈরি'),
  followUpBody: (name: string) => pick(lang,
    `Follow-up message ready for ${name}`,
    `${name} के लिए मैसेज तैयार है`,
    `${name}-এর জন্য মেসেজ তৈরি`),

  enquiryTitle: (first: string) => pick(lang,
    `New enquiry from ${first}`,
    `${first} की नई पूछताछ`,
    `${first}-এর নতুন জিজ্ঞাসা`),
  enquiryBody: (kind: EnquiryNotice) => ({
    calling: pick(lang,
      'Your AI employee is calling them now.',
      'आपका AI कर्मचारी अभी उन्हें कॉल कर रहा है।',
      'আপনার AI কর্মী এখন তাঁকে কল করছে।'),
    scheduled: pick(lang,
      'Your AI employee will call them when calling hours start.',
      'कॉल का समय शुरू होते ही आपका AI कर्मचारी उन्हें कॉल करेगा।',
      'কলের সময় শুরু হলেই আপনার AI কর্মী তাঁকে কল করবে।'),
    manual: pick(lang,
      'Auto-call is off. Open the lead to call them.',
      'ऑटो कॉल बंद है। कॉल करने के लिए ग्राहक खोलें।',
      'অটো কল বন্ধ। কল করতে গ্রাহক খুলুন।'),
    not_called_dnc: pick(lang,
      'Not called: this number is on your do-not-call list.',
      'कॉल नहीं हुई: यह नंबर आपकी "कॉल न करें" सूची में है।',
      'কল হয়নি: এই নম্বর আপনার "কল করবেন না" তালিকায় আছে।'),
    not_called_minutes: pick(lang,
      'Not called: add calling minutes to auto-call new enquiries.',
      'कॉल नहीं हुई: नई पूछताछ पर अपने-आप कॉल के लिए मिनट जोड़ें।',
      'কল হয়নি: নতুন জিজ্ঞাসায় নিজে থেকে কলের জন্য মিনিট যোগ করুন।'),
    not_called_failed: pick(lang,
      'The AI call could not be placed. Open the lead to try again.',
      'AI कॉल नहीं लग पाई। दोबारा कोशिश के लिए ग्राहक खोलें।',
      'AI কল করা যায়নি। আবার চেষ্টা করতে গ্রাহক খুলুন।'),
  }[kind]),
  view: pick(lang, 'View', 'देखें', 'দেখুন'),

  sourceErrorTitle: (source: string) => pick(lang,
    `${source} connection stopped working`,
    `${source} का कनेक्शन बंद हो गया`,
    `${source}-এর সংযোগ বন্ধ হয়ে গেছে`),
  sourceErrorBody: pick(lang,
    'New leads are not coming in. Open "Get leads automatically" and connect it again.',
    'नए ग्राहक नहीं आ रहे। "नए ग्राहक अपने-आप पाएँ" खोलें और फिर से जोड़ें।',
    'নতুন গ্রাহক আসছে না। "নতুন গ্রাহক নিজে থেকে পান" খুলে আবার যুক্ত করুন।'),
  fix: pick(lang, 'Fix', 'ठीक करें', 'ঠিক করুন'),

  digestTitle: pick(lang, 'Your day with CallPilot', 'CallPilot के साथ आपका दिन', 'CallPilot-এর সঙ্গে আপনার দিন'),
  digestCalls: (n: number) => pick(lang,
    `${n} ${n === 1 ? 'call' : 'calls'}`, `${n} कॉल`, `${n}টি কল`),
  digestReady: (n: number) => pick(lang, `${n} ready to buy`, `${n} खरीदने को तैयार`, `${n} জন কিনতে তৈরি`),
  digestInterested: (n: number) => pick(lang, `${n} interested`, `${n} को रुचि है`, `${n} জন আগ্রহী`),
  digestEnquiries: (n: number) => pick(lang,
    `${n} ${n === 1 ? 'new enquiry' : 'new enquiries'}`, `${n} नई पूछताछ`, `${n}টি নতুন জিজ্ঞাসা`),
  digestCallbacks: (n: number) => pick(lang,
    `${n} ${n === 1 ? 'callback tomorrow' : 'callbacks tomorrow'}`, `कल ${n} कॉल बैक`, `কাল ${n}টি কল ব্যাক`),
  digestSeeThem: pick(lang, 'tap to see them', 'देखने के लिए टैप करें', 'দেখতে ট্যাপ করুন'),
  digestSeeMore: pick(lang, 'tap to see more', 'और देखने के लिए टैप करें', 'আরও দেখতে ট্যাপ করুন'),
  digestBody: (parts: string[], cta: string) => pick(lang,
    `Today: ${parts.join(', ')} — ${cta}`,
    `आज: ${parts.join(', ')} — ${cta}`,
    `আজ: ${parts.join(', ')} — ${cta}`),
  seeResults: pick(lang, 'See results', 'नतीजे देखें', 'ফলাফল দেখুন'),

  upiConfirmedTitle: pick(lang, 'Payment received', 'पेमेंट मिल गया', 'পেমেন্ট পাওয়া গেছে'),
  upiConfirmedBody: (what: string) => pick(lang,
    `Thank you! ${what} is now active.`,
    `धन्यवाद! ${what} अब चालू है।`,
    `ধন্যবাদ! ${what} এখন চালু।`),
  upiRejectedTitle: pick(lang, 'We couldn’t find your payment', 'आपका पेमेंट नहीं मिला', 'আপনার পেমেন্ট পাওয়া যায়নি'),
  upiRejectedBody: (reference: string) => pick(lang,
    `No UPI payment matched reference ${reference}. Check the UTR in your UPI app and enter it again, or email us.`,
    `रेफ़रेंस ${reference} से कोई UPI पेमेंट नहीं मिला। अपने UPI ऐप में UTR देखकर फिर से डालें, या हमें ईमेल करें।`,
    `রেফারেন্স ${reference}-এর সঙ্গে কোনো UPI পেমেন্ট মেলেনি। আপনার UPI অ্যাপে UTR দেখে আবার দিন, অথবা আমাদের ইমেল করুন।`),
});
