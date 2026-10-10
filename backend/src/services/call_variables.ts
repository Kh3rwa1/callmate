/**
 * agent_variables for an outbound Sarvam call, shared by the manual dial (routes/calls.ts) and
 * campaign dispatch (services/campaign_queue.ts).
 *
 * Sarvam rejects the WHOLE dial (422 "Agent variables ... not found in agent variables of app")
 * if we send a variable the agent version does not declare. So only names on the allow-list
 * SARVAM_AGENT_VARIABLES are sent; unset = DEFAULT_AGENT_VARIABLES, the ones the agent declares
 * today. To use an optional variable: declare it in the Sarvam agent, commit a version, bump
 * SARVAM_APP_VERSION, then add the name to SARVAM_AGENT_VARIABLES (docs/SARVAM_SETUP.md).
 */
import { Env } from '../types';
import { voiceAgentVariables } from './voice_persona';
import { topKnowledge } from './knowledge';
import { ROLE_GOALS } from './prompt';
import { safeJsonParse } from '../utils/json';

/** Declared in the Sarvam agent today; sent when SARVAM_AGENT_VARIABLES is unset. */
export const DEFAULT_AGENT_VARIABLES = [
  'call_id', 'campaign_id', 'lead_id', 'lead_name', 'business_name', 'agent_name', 'agent_role', 'interest',
] as const;

/** Opt-in extras: only sent once listed in SARVAM_AGENT_VARIABLES. */
export const OPTIONAL_AGENT_VARIABLES = [
  'gender', 'voice', 'speaker', 'language_code', 'tts_model', 'business_context', 'call_language',
] as const;

export const KNOWN_AGENT_VARIABLES: readonly string[] = [...DEFAULT_AGENT_VARIABLES, ...OPTIONAL_AGENT_VARIABLES];

export const BUSINESS_CONTEXT_MAX_CHARS = 1500;

export interface CallVariableInput {
  businessId: string;
  business?: { name?: string | null } | null;
  agent?: { name?: string | null; role?: string | null; voice?: string | null; languages?: string | string[] | null; goal?: string | null } | null;
  lead: { id: string; name: string; interest?: string | null; course_interest?: string | null };
  callId: string;
  campaignId?: string | null;
  /** Knowledge snippets for business_context; loaded from the knowledge base when omitted. */
  knowledge?: string[];
}

/** Names to send: SARVAM_AGENT_VARIABLES (comma separated) or the default 8. Unknown names are dropped. */
export function allowedAgentVariables(env: Pick<Env, 'SARVAM_AGENT_VARIABLES'>): string[] {
  const raw = (env.SARVAM_AGENT_VARIABLES || '').split(',').map((s) => s.trim()).filter(Boolean);
  if (raw.length === 0) return [...DEFAULT_AGENT_VARIABLES];
  const unknown = raw.filter((n) => !KNOWN_AGENT_VARIABLES.includes(n));
  if (unknown.length) {
    console.warn(JSON.stringify({ msg: 'unknown_agent_variables_ignored', names: unknown, known: KNOWN_AGENT_VARIABLES }));
  }
  return [...new Set(raw.filter((n) => KNOWN_AGENT_VARIABLES.includes(n)))];
}

/** The employee's first language as the owner named it ("Hindi"); English if none. */
export function firstLanguageName(languages?: string | string[] | null): string {
  const list = typeof languages === 'string' ? safeJsonParse<unknown>(languages, [languages]) : languages;
  const first = Array.isArray(list) ? String(list[0] ?? '').trim() : '';
  return first || 'English';
}

function clip(s: string, max: number): string {
  return s.length <= max ? s : `${s.slice(0, Math.max(0, max - 1)).trimEnd()}…`;
}

/**
 * Compact plain-text summary of the business for the call agent: profile fields that exist plus
 * the top knowledge snippets, capped at `max` characters.
 */
export function formatBusinessContext(business: any, agent: any, knowledge: string[], max = BUSINESS_CONTEXT_MAX_CHARS): string {
  const lines: string[] = [];
  const b = business ?? {};
  const name = (b.name || '').trim();
  const category = (b.category || '').trim();
  if (name) lines.push(`Business: ${name}${category && category !== 'other' ? ` (${category.replace(/_/g, ' ')})` : ''}`);
  const offerings = safeJsonParse<unknown>(b.offerings, []);
  if (Array.isArray(offerings) && offerings.length) lines.push(`Offerings: ${offerings.map(String).join(', ')}`);
  if (b.pricing) lines.push(`Pricing: ${String(b.pricing).trim()}`);
  if (b.opening_hours) lines.push(`Hours: ${String(b.opening_hours).trim()}`);
  const place = [b.address, b.location].filter((x) => x && String(x).trim()).map((x) => String(x).trim());
  if (place.length) lines.push(`Location: ${[...new Set(place)].join(', ')}`);
  const goal = (agent?.goal || '').trim() || ROLE_GOALS[category] || '';
  if (goal) lines.push(`Goal: ${goal}`);
  const facts = knowledge.map((k) => k.replace(/\s+/g, ' ').trim()).filter(Boolean);
  if (facts.length) lines.push(`Facts:\n${facts.map((f) => `- ${clip(f, 400)}`).join('\n')}`);
  return clip(lines.join('\n'), max);
}

/**
 * Every candidate variable for this call, filtered to the allow-list. Expensive candidates
 * (business_context reads the business row and knowledge base) are only built when allowed.
 * Never returns null/undefined values.
 */
export async function buildCallAgentVariables(env: Env, input: CallVariableInput): Promise<Record<string, string>> {
  const allowed = allowedAgentVariables(env);
  const { agent, lead } = input;
  const candidates: Record<string, () => string | Promise<string>> = {
    call_id: () => input.callId,
    campaign_id: () => input.campaignId ?? '',
    lead_id: () => lead.id,
    lead_name: () => lead.name,
    business_name: () => input.business?.name ?? 'our business',
    agent_name: () => agent?.name ?? 'Assistant',
    agent_role: () => agent?.role ?? 'Assistant',
    interest: () => lead.interest ?? lead.course_interest ?? '',
    call_language: () => firstLanguageName(agent?.languages),
    business_context: async () => {
      const business = await env.DB.prepare('SELECT * FROM businesses WHERE id = ?').bind(input.businessId).first<any>();
      const knowledge = input.knowledge
        ?? await topKnowledge(env, input.businessId, lead.interest ?? lead.course_interest, 3).catch(() => []);
      return formatBusinessContext(business ?? input.business, agent, knowledge);
    },
  };
  const voice = voiceAgentVariables(agent);
  for (const [k, v] of Object.entries(voice)) candidates[k] = () => String(v);

  const out: Record<string, string> = {};
  for (const name of allowed) {
    const make = candidates[name];
    if (make) out[name] = String((await make()) ?? '');
  }
  return out;
}
