/**
 * Enforced AI + recording disclosure for outbound calls (TRAI / DPDP transparency).
 *
 * Sarvam's outbound API lets a dial override the agent's first utterance
 * (`app_config.app_overrides.initial_bot_message`) and its starting language
 * (`initial_language_name`). With SARVAM_DISCLOSURE_OVERRIDE = 'true' every dial (manual and
 * campaign; both go through dialSarvam) opens with a fixed sentence saying the caller is an AI
 * assistant, which business it calls for, and that the call may be recorded. The text is ours,
 * so a prompt edit in the Sarvam dashboard can't silently drop the disclosure.
 *
 * Off by default: turn it on only after a staging test call confirms the agent version accepts
 * the override (docs/SARVAM_SETUP.md -> Disclosure override).
 */
import { Env } from '../types';
import { callLang, VoiceLang } from './voice_persona';

/** `initial_language_name` values we send (a subset of Sarvam's enum). */
export type SarvamLanguageName = 'English' | 'Hindi' | 'Bengali';

export interface SarvamAppOverrides {
  initial_bot_message: string;
  initial_language_name: SarvamLanguageName;
}

/** Longest name (lead, agent or business) spoken in the disclosure. */
export const DISCLOSURE_NAME_MAX = 40;

const LANGUAGE_NAMES: Record<VoiceLang, SarvamLanguageName> = { en: 'English', hi: 'Hindi', bn: 'Bengali' };

export function disclosureEnabled(env: Pick<Env, 'SARVAM_DISCLOSURE_OVERRIDE'>): boolean {
  return (env.SARVAM_DISCLOSURE_OVERRIDE || '').trim().toLowerCase() === 'true';
}

/**
 * A name safe to speak: no control characters, no template/markup characters ({}[]<>`\"$|),
 * single spaces, at most `max` characters (cut at a word boundary when possible).
 * Empty input gives `fallback`.
 */
export function safeSpokenName(raw: unknown, fallback: string, max = DISCLOSURE_NAME_MAX): string {
  const cleaned = String(raw ?? '')
    .normalize('NFC')
    .replace(/[\p{Cc}\p{Cf}]/gu, ' ')
    .replace(/[{}[\]<>`\\"$|]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
  if (!cleaned) return fallback;
  if (cleaned.length <= max) return cleaned;
  const cut = cleaned.slice(0, max);
  const lastSpace = cut.lastIndexOf(' ');
  return (lastSpace >= max / 2 ? cut.slice(0, lastSpace) : cut).trim();
}

export interface DisclosureNames {
  lead?: string | null;
  agent?: string | null;
  business?: string | null;
}

/** The opening sentence in the call language. Names are sanitised here. */
export function disclosureMessage(lang: VoiceLang, names: DisclosureNames): string {
  const lead = safeSpokenName(names.lead, '');
  const agent = safeSpokenName(names.agent, lang === 'en' ? 'Assistant' : lang === 'hi' ? 'सहायक' : 'সহকারী');
  const business = safeSpokenName(names.business, lang === 'en' ? 'our team' : lang === 'hi' ? 'हमारी टीम' : 'আমাদের টিম');
  // The business comes first so the lead knows who is calling before anything else.
  switch (lang) {
    case 'hi':
      return `नमस्ते${lead ? ` ${lead}` : ''}, ${business} की ओर से आपकी पूछताछ के बारे में कॉल है। `
        + `मैं ${agent} हूँ, एक AI सहायक। गुणवत्ता के लिए यह कॉल रिकॉर्ड की जा सकती है। `
        + 'क्या अभी बात करने का सही समय है?';
    case 'bn':
      return `নমস্কার${lead ? ` ${lead}` : ''}, ${business} থেকে আপনার জিজ্ঞাসার বিষয়ে ফোন করছি। `
        + `আমি ${agent}, একজন AI সহকারী। মান বজায় রাখতে এই কলটি রেকর্ড করা হতে পারে। `
        + 'এখন কি কথা বলার সুবিধাজনক সময়?';
    default:
      return `Hello${lead ? ` ${lead}` : ''}, I'm calling from ${business} about your enquiry. `
        + `This is ${agent}, an AI assistant. This call may be recorded for quality. Is this a good time to talk?`;
  }
}

/**
 * The first thing the agent says in the owner's in-app test ("Talk to <agent>"), passed to the Sarvam
 * SDK as initial_bot_message so it replaces the agent's default greeting from the Sarvam dashboard.
 * Business first, like the outbound disclosure.
 */
export function testGreeting(lang: VoiceLang, names: Pick<DisclosureNames, 'agent' | 'business'>): SarvamAppOverrides {
  const agent = safeSpokenName(names.agent, lang === 'en' ? 'Assistant' : lang === 'hi' ? 'सहायक' : 'সহকারী');
  const business = safeSpokenName(names.business, lang === 'en' ? 'our team' : lang === 'hi' ? 'हमारी टीम' : 'আমাদের টিম');
  const message = lang === 'hi'
    ? `नमस्ते, ${business} की ओर से। मैं ${agent} हूँ, AI सहायक। बताइए, मैं आपकी क्या मदद करूँ?`
    : lang === 'bn'
      ? `নমস্কার, ${business} থেকে বলছি। আমি ${agent}, AI সহকারী। বলুন, কীভাবে সাহায্য করতে পারি?`
      : `Hello, this is ${business}. I'm ${agent}, the AI assistant. How can I help you today?`;
  return { initial_bot_message: message, initial_language_name: LANGUAGE_NAMES[lang] };
}

/**
 * What the AI says when it answers a call the owner missed (services/answering.ts): which business,
 * that it is an AI assistant and the call may be recorded, then an offer to help. With no business
 * (the number isn't assigned), a neutral version.
 */
export function inboundGreeting(lang: VoiceLang, names: Pick<DisclosureNames, 'agent' | 'business'>): string {
  const agent = safeSpokenName(names.agent, lang === 'en' ? 'an assistant' : lang === 'hi' ? 'सहायक' : 'সহকারী');
  const business = safeSpokenName(names.business, '');
  switch (lang) {
    case 'hi':
      return `नमस्ते${business ? `, ${business}` : ''}। मैं ${agent} हूँ, एक AI सहायक। `
        + 'अभी टीम फ़ोन नहीं उठा पा रही, पर मैं आपकी मदद कर सकती हूँ। यह कॉल रिकॉर्ड की जा सकती है। बताइए, क्या जानना है?';
    case 'bn':
      return `নমস্কার${business ? `, ${business}` : ''}। আমি ${agent}, একজন AI সহকারী। `
        + 'এখন টিম ফোন ধরতে পারছে না, তবে আমি সাহায্য করতে পারি। এই কলটি রেকর্ড হতে পারে। বলুন, কী জানতে চান?';
    default:
      return `Hello${business ? `, you've reached ${business}` : ''}. I'm ${agent}, an AI assistant. `
        + "The team can't come to the phone right now, but I can help. This call may be recorded. What can I do for you?";
  }
}

export interface DisclosureInput {
  agent?: { name?: string | null; languages?: string | string[] | null } | null;
  business?: { name?: string | null } | null;
  lead: { name?: string | null };
}

/**
 * app_overrides for a dial, or undefined when SARVAM_DISCLOSURE_OVERRIDE is not 'true'
 * (dialSarvam then sends no app_overrides at all). Language = the employee's first language.
 */
export function buildDisclosureOverrides(
  env: Pick<Env, 'SARVAM_DISCLOSURE_OVERRIDE'>, input: DisclosureInput,
): SarvamAppOverrides | undefined {
  if (!disclosureEnabled(env)) return undefined;
  const lang = callLang(input.agent?.languages);
  // Only the first name: friendlier and leaks less if the wrong person answers.
  const leadFirst = safeSpokenName(input.lead?.name, '').split(' ')[0] ?? '';
  return {
    initial_bot_message: disclosureMessage(lang, {
      lead: leadFirst,
      agent: input.agent?.name,
      business: input.business?.name,
    }),
    initial_language_name: LANGUAGE_NAMES[lang],
  };
}
