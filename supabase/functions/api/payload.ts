import type { CreateCampaignInput, StartOutboundCallInput } from "./voice/types.ts"

/**
 * Builds the provider payloads from our own records.
 *
 * The agent variables are the contract that makes structured outcomes possible:
 * we tell Sarvam's agent which fields to collect during the call
 * (outcome, appointment_booked, appointment_date, follow_up_required,
 * payment_recovered, amount_recovered, customer_intent, notes), and the webhook
 * sends those values back. Our own ids travel in `metadata` so a returning event
 * can be matched to the exact call and tenant.
 */

export const AGENT_VARIABLE_SCHEMA: Record<string, string> = {
  outcome: "booked | interested | follow_up | recovered | not_interested | no_response",
  appointment_booked: "boolean",
  appointment_date: "YYYY-MM-DD or null",
  appointment_time: "HH:MM or null",
  follow_up_required: "boolean",
  follow_up_date: "YYYY-MM-DD or null",
  payment_recovered: "boolean",
  amount_recovered: "number or null",
  customer_intent: "short string",
  notes: "short string",
}

export function encodeAgentVariables(input: {
  contactName: string
  service: string
  businessName: string
  agentName: string
  language: string
  callStyle: string
  greeting: string | null
}): Record<string, unknown> {
  return {
    customer_name: input.contactName,
    service: input.service,
    business_name: input.businessName,
    agent_name: input.agentName,
    language: input.language,
    call_style: input.callStyle,
    greeting: input.greeting,
    // The structured fields the agent must return when the call ends.
    required_output_fields: Object.keys(AGENT_VARIABLE_SCHEMA),
    output_schema: AGENT_VARIABLE_SCHEMA,
  }
}

export function toOutboundInput(args: {
  deploymentId: string
  appVersion: number
  contact: Record<string, unknown>
  phone: Record<string, unknown> | null
  agent: Record<string, unknown> | null
  webhookUrl: string
  callId: string
}): StartOutboundCallInput {
  return {
    deploymentId: args.deploymentId,
    appVersion: args.appVersion,
    customerPhone: normalisePhone(String(args.contact.phone)),
    variables: encodeAgentVariables({
      contactName: String(args.contact.name),
      service: String(args.contact.service ?? "Enquiry"),
      businessName: String(args.agent?.business_name ?? ""),
      agentName: String(args.agent?.name ?? "Shampy"),
      language: String(args.agent?.language ?? "Hindi"),
      callStyle: String(args.agent?.call_style ?? "Friendly"),
      greeting: (args.agent?.greeting as string | null) ?? null,
    }),
    agentPhoneNumber: (args.phone?.number as string | undefined) ?? null,
    connectionId: (args.phone?.connection_id as string | undefined) ?? null,
    webhookUrl: args.webhookUrl,
    metadata: {
      callId: args.callId,
      contactId: args.contact.id,
      organizationId: "org_demo",
    },
  }
}

export function toCampaignInput(args: {
  name: string
  deploymentId: string
  appVersion: number
  phone: Record<string, unknown> | null
  agent: Record<string, unknown> | null
  webhookUrl: string
  campaignId: string
  scheduledFor: string | null
}): CreateCampaignInput {
  const start = args.scheduledFor ? new Date(args.scheduledFor) : new Date()
  const end = new Date(start.getTime())
  end.setDate(end.getDate() + 30)

  return {
    name: args.name,
    description: "Outbound calling round started from Callmate",
    deploymentId: args.deploymentId,
    appVersion: args.appVersion,
    agentPhoneNumber: (args.phone?.number as string | undefined) ?? null,
    connectionId: (args.phone?.connection_id as string | undefined) ?? null,
    startTimestamp: start.toISOString(),
    endTimestamp: end.toISOString(),
    // Calling is only allowed inside the business's working hours.
    allowedSchedule: {
      timezone: "Asia/Kolkata",
      days: ["mon", "tue", "wed", "thu", "fri", "sat"],
      start_time: (args.agent?.working_hours_start as string | undefined) ?? "09:00",
      end_time: (args.agent?.working_hours_end as string | undefined) ?? "19:00",
    },
    webhookUrl: args.webhookUrl,
    metadata: { campaignId: args.campaignId, organizationId: "org_demo" },
  }
}

/** Strips formatting so the provider receives E.164-ish digits with a leading +. */
export function normalisePhone(phone: string): string {
  const digits = phone.replace(/[^\d]/g, "")
  return digits.length > 10 ? `+${digits}` : `+91${digits}`
}

export function phoneIsValid(phone: string): boolean {
  const digits = phone.replace(/[^\d]/g, "")
  return digits.length >= 10 && digits.length <= 13
}
