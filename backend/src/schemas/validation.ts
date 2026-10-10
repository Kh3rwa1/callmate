import { z } from 'zod';
import { TRAI_EARLIEST_HOUR, TRAI_LATEST_HOUR } from '../services/compliance';

// ==========================================
// Auth Schemas
// ==========================================
export const otpRequestSchema = z.object({
  phone: z.string().min(8, 'Phone number must be at least 8 digits').max(16, 'Phone number too long'),
});

export const registerSchema = z.object({
  phone: z.string().min(8, 'Phone number must be at least 8 digits').max(16, 'Phone number too long'),
  otp: z.string().length(6, 'OTP must be exactly 6 digits'),
  business_name: z.string().min(1, 'Business name is required').max(120),
});

export const loginSchema = z.object({
  phone: z.string().min(8, 'Phone number must be at least 8 digits').max(16, 'Phone number too long'),
  otp: z.string().length(6, 'OTP must be exactly 6 digits'),
});

export const googleSignInSchema = z.object({
  id_token: z.string().min(100, 'Invalid sign-in token').max(4096),
  business_name: z.string().max(120).optional(),
  phone: z.string().max(16).optional(),
});

export const refreshSchema = z.object({
  refresh_token: z.string().min(20, 'Invalid refresh token format'),
});

export const consentEnum = z.enum([
  'explicit_opt_in',
  'inquiry',
  'existing_customer',
  'unknown',
  'opt_out',
]);

// ==========================================
// Lead Schemas
// ==========================================
export const createLeadSchema = z.object({
  name: z.string().min(1, 'Name is required').max(100),
  phone: z.string().min(8, 'Phone number must be at least 8 digits').max(20),
  interest: z.string().nullable().optional(),
  course_interest: z.string().nullable().optional(),
  source: z.string().optional(),
  attributes: z.record(z.string(), z.any()).optional(),
  do_not_call: z.boolean().optional(),
  consent: consentEnum.optional(),
  timezone: z.string().optional(),
});

export const leadItemSchema = z.object({
  name: z.string().min(1, 'Name is required').max(100),
  phone: z.string().min(8, 'Phone must be at least 8 digits').max(20),
  interest: z.string().nullable().optional(),
  course_interest: z.string().nullable().optional(),
  source: z.string().optional(),
  attributes: z.record(z.string(), z.any()).optional(),
  do_not_call: z.boolean().optional(),
  consent: consentEnum.optional(),
});

export const importLeadsSchema = z.object({
  leads: z.array(leadItemSchema).min(1, 'At least 1 lead is required').max(1000, 'Import batch cannot exceed 1000 leads'),
});

export const patchLeadSchema = z.object({
  name: z.string().min(1).max(100).optional(),
  phone: z.string().min(8).max(20).optional(),
  interest: z.string().nullable().optional(),
  course_interest: z.string().nullable().optional(),
  status: z.enum(['new', 'calling', 'called', 'interested', 'hot', 'warm', 'cold', 'lost']).optional(),
  temperature: z.enum(['hot', 'warm', 'cold']).nullable().optional(),
  score: z.number().int().min(0).max(100).nullable().optional(),
  summary: z.string().nullable().optional(),
  objections: z.array(z.string()).optional(),
  next_action: z.string().optional(),
  callback_at: z.string().nullable().optional(),
  attributes: z.record(z.string(), z.any()).optional(),
  do_not_call: z.boolean().optional(),
  consent: consentEnum.optional(),
  timezone: z.string().optional(),
});

// ==========================================
// Campaign Schemas
// ==========================================
const TRAI_HOURS_MESSAGE = `Calls are only allowed between ${TRAI_EARLIEST_HOUR}:00 and ${TRAI_LATEST_HOUR}:00 (TRAI)`;

export const startCampaignSchema = z.object({
  consent_attestation: z.boolean().optional(),
});
export const MAX_CAMPAIGN_LEADS = 500;
export const createCampaignSchema = z.object({
  purpose: z.string().min(1, 'Campaign purpose is required').max(255).optional(),
  title: z.string().min(1).max(255).optional(),
  lead_ids: z.array(z.string()).max(MAX_CAMPAIGN_LEADS, `A campaign can include at most ${MAX_CAMPAIGN_LEADS} leads`).default([]),
  // TRAI window 09:00-21:00 local time. Exclusive end hour: calls allowed while hour < end.
  calling_hours_start: z.number().int().min(TRAI_EARLIEST_HOUR, TRAI_HOURS_MESSAGE).max(TRAI_LATEST_HOUR - 1, TRAI_HOURS_MESSAGE).default(10),
  calling_hours_end: z.number().int().min(TRAI_EARLIEST_HOUR + 1, TRAI_HOURS_MESSAGE).max(TRAI_LATEST_HOUR, TRAI_HOURS_MESSAGE).default(19),
  options: z.record(z.string(), z.any()).optional(),
}).refine((d) => d.calling_hours_start < d.calling_hours_end, {
  message: 'Calling hours start must be before calling hours end',
  path: ['calling_hours_end'],
});

// ==========================================
// Knowledge Schemas
// ==========================================
export const knowledgeTypeEnum = z.enum(['text', 'faq', 'business_info', 'notes', 'website', 'document', 'file', 'pdf']);
export const createKnowledgeSchema = z.object({
  type: knowledgeTypeEnum.default('text'),
  title: z.string().max(200, 'Title cannot exceed 200 characters').nullable().optional(),
  content: z.string().max(200_000, 'Content cannot exceed 200,000 characters').nullable().optional(),
  url: z.string().max(2048, 'URL too long').nullable().optional(),
});

// ==========================================
// Business & Agent Schemas
// ==========================================
export const patchBusinessSchema = z.object({
  name: z.string().min(1).max(100).optional(),
  category: z.string().optional(),
  address: z.string().nullable().optional(),
  offerings: z.array(z.string()).optional(),
  pricing: z.string().nullable().optional(),
  opening_hours: z.string().nullable().optional(),
  location: z.string().nullable().optional(),
  whatsapp_number: z.string().nullable().optional(),
  human_number: z.string().nullable().optional(),
  owner_name: z.string().nullable().optional(),
  /** Daily 19:00 summary push (services/digest.ts). */
  digest_enabled: z.boolean().optional(),
  /** Average sale value for the results card's revenue estimate; null clears it. */
  avg_deal_value_inr: z.number().int().min(1).max(100_000_000).nullable().optional(),
});

/** POST /agent/test-call: the owner's own mobile number. */
export const ownerTestCallSchema = z.object({
  phone: z.string().min(8).max(20),
});

export const patchAgentSchema = z.object({
  name: z.string().min(1).max(100).optional(),
  role: z.string().optional(),
  role_kind: z.string().optional(),
  template_id: z.string().optional(),
  skills: z.array(z.string()).optional(),
  languages: z.array(z.string()).optional(),
  goal: z.string().optional(),
  formality: z.number().min(0).max(1).optional(),
  capabilities: z.array(z.string()).optional(),
  calling_hours_start: z.number().int().min(TRAI_EARLIEST_HOUR, TRAI_HOURS_MESSAGE).max(TRAI_LATEST_HOUR - 1, TRAI_HOURS_MESSAGE).optional(),
  calling_hours_end: z.number().int().min(TRAI_EARLIEST_HOUR + 1, TRAI_HOURS_MESSAGE).max(TRAI_LATEST_HOUR, TRAI_HOURS_MESSAGE).optional(),
  transfer_number: z.string().nullable().optional(),
  voice: z.string().optional(),
  status: z.enum(['active', 'paused', 'inactive']).optional(),
}).refine((d) => d.calling_hours_start === undefined || d.calling_hours_end === undefined || d.calling_hours_start < d.calling_hours_end, {
  message: 'Calling hours start must be before calling hours end',
  path: ['calling_hours_end'],
});

// ==========================================
// Followup & Callback Schemas
// ==========================================
export const patchFollowupSchema = z.object({
  message: z.string().optional(),
  status: z.enum(['ready', 'opened', 'done', 'dismissed']).optional(),
  opened_at: z.string().nullable().optional(),
});

export const createCallbackSchema = z.object({
  lead_id: z.string().min(1, 'Lead ID is required'),
  scheduled_at: z.string().min(1, 'Scheduled time is required'),
  note: z.string().nullable().optional(),
});

export const patchCallbackSchema = z.object({
  status: z.enum(['scheduled', 'done']).optional(),
  note: z.string().nullable().optional(),
});

export const deviceTokenSchema = z.object({
  token: z.string().min(1, 'Token is required'),
  platform: z.enum(['android', 'ios', 'web']).default('android'),
});

/**
 * Helper to validate a request body with a Zod schema.
 * Returns { success: true, data } or { success: false, response: Response }
 */
export async function parseJsonBody<T>(c: any, schema: z.ZodType<T>): Promise<{ success: true; data: T } | { success: false; response: Response }> {
  let raw: any;
  try {
    raw = await c.req.json();
  } catch {
    return {
      success: false,
      response: c.json({ message: 'Malformed JSON payload.', code: 'invalid_json' }, 400),
    };
  }

  return parseData(c, schema, raw);
}

/** Validates already-parsed input (e.g. multipart fields) with the same error shape as parseJsonBody. */
export function parseData<T>(c: any, schema: z.ZodType<T>, raw: unknown): { success: true; data: T } | { success: false; response: Response } {
  const result = schema.safeParse(raw);
  if (!result.success) {
    const issues = (result.error as any).issues || (result.error as any).errors || [];
    const errorDetails = issues.map((e: any) => ({
      field: Array.isArray(e.path) ? e.path.join('.') : String(e.path || ''),
      message: e.message,
    }));
    return {
      success: false,
      response: c.json({
        message: issues[0]?.message || 'Validation error',
        code: 'validation_error',
        errors: errorDetails,
      }, 400),
    };
  }

  return { success: true, data: result.data };
}
