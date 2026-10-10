/**
 * Which voice the AI employee speaks with. The owner picks a man's or a
 * woman's voice; the stored label ("Warm · Female", "Friendly · Male",
 * "Friendly Female (Hindi/English)") carries the gender.
 *
 * Speaker IDs are Sarvam Bulbul v4 Flash personas (docs.sarvam.ai → Voices).
 * "meera" is a Bulbul v1 name and is not in the v4 catalog.
 */
export type VoiceGender = 'female' | 'male';
export type VoiceLang = 'en' | 'hi' | 'bn';

const SPEAKERS: Record<VoiceLang, Record<VoiceGender, string>> = {
  // English for Indian callers: the English–Hindi code-mixed personas.
  en: { female: 'ishita_enhi_customer', male: 'sunny_enhi_customer' },
  hi: { female: 'ritu_hi_customer', male: 'shubh_hi_customer' },
  bn: { female: 'roopa_bn_conversational', male: 'bappa_bn_conversation' },
};

const LANGUAGE_CODES: Record<VoiceLang, string> = { en: 'en-IN', hi: 'hi-IN', bn: 'bn-IN' };

/** "female" wins ties because the word contains "male". Unknown → female. */
export function voiceGender(voice?: string | null): VoiceGender {
  const v = (voice || '').toLowerCase();
  if (v.includes('female') || v.includes('woman')) return 'female';
  return /\b(male|man)\b/.test(v) ? 'male' : 'female';
}

export function voiceLang(lang?: unknown): VoiceLang {
  return lang === 'hi' || lang === 'bn' ? lang : 'en';
}

export function sarvamSpeaker(gender: VoiceGender, lang: VoiceLang = 'en'): string {
  return SPEAKERS[lang][gender];
}

export function sarvamLanguageCode(lang: VoiceLang = 'en'): string {
  return LANGUAGE_CODES[lang];
}

/** Deepgram Aura 2 fallback voice (Cloudflare Workers AI). */
export function auraVoice(gender: VoiceGender): string {
  return gender === 'male' ? 'orion' : 'luna';
}
