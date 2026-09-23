import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2"

import { ApiError, notConfigured } from "./_http.ts"
import type { NormalisedOutcome, ContactStatusValue, StructuredAgentResult } from "./voice/outcome.ts"

export const ORGANIZATION_ID = "org_demo"

/** Service-role client. The only client that can touch our tables, by design. */
export function db(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL")
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
  if (!url || !key) throw new ApiError("server_error", 500, "The service is not configured correctly.")
  return createClient(url, key, { auth: { persistSession: false } })
}

export type OrgConfig = {
  id: string
  name: string
  voiceMode: string
  sarvamOrgId: string | null
  sarvamWorkspaceId: string | null
  sarvamDeploymentId: string | null
  sarvamAppVersion: number
}

export async function getOrgConfig(client: SupabaseClient, orgId = ORGANIZATION_ID): Promise<OrgConfig> {
  const { data, error } = await client
    .from("organizations")
    .select("id, name, voice_mode, sarvam_org_id, sarvam_workspace_id, sarvam_deployment_id, sarvam_app_version")
    .eq("id", orgId)
    .maybeSingle()

  if (error) throw new ApiError("server_error", 500, "We couldn't load your account. Please try again.")
  if (!data) throw new ApiError("not_found", 404, "We couldn't find your business account.")

  return {
    id: data.id,
    name: data.name,
    voiceMode: data.voice_mode,
    sarvamOrgId: data.sarvam_org_id,
    sarvamWorkspaceId: data.sarvam_workspace_id,
    sarvamDeploymentId: data.sarvam_deployment_id,
    sarvamAppVersion: data.sarvam_app_version,
  }
}

export async function requireDeployment(org: OrgConfig): Promise<string> {
  if (!org.sarvamDeploymentId) throw notConfigured("Sarvam deployment id is missing for this organization")
  return org.sarvamDeploymentId
}

export async function getPhoneNumberRow(client: SupabaseClient, orgId = ORGANIZATION_ID) {
  const { data } = await client
    .from("phone_numbers")
    .select("*")
    .eq("organization_id", orgId)
    .maybeSingle()
  return data
}

export async function getAgentRow(client: SupabaseClient, orgId = ORGANIZATION_ID) {
  const { data } = await client.from("ai_agents").select("*").eq("organization_id", orgId).maybeSingle()
  return data
}

export async function getUsageRow(client: SupabaseClient, orgId = ORGANIZATION_ID) {
  const { data } = await client.from("org_usage").select("*").eq("organization_id", orgId).maybeSingle()
  return data
}

export async function checkCredits(client: SupabaseClient, orgId = ORGANIZATION_ID) {
  const usage = await getUsageRow(client, orgId)
  if (usage && Number(usage.credits_remaining) <= 0) {
    throw new ApiError(
      "insufficient_credits",
      402,
      "You've run out of calling credits this month. Renew your plan to keep calling."
    )
  }
}

export async function listContacts(client: SupabaseClient, orgId = ORGANIZATION_ID) {
  const { data, error } = await client
    .from("contacts")
    .select("*")
    .eq("organization_id", orgId)
    .order("created_at", { ascending: false })
  if (error) throw new ApiError("server_error", 500, "We couldn't load your customers.")
  return data ?? []
}

export async function getContact(client: SupabaseClient, contactId: string, orgId = ORGANIZATION_ID) {
  const { data } = await client
    .from("contacts")
    .select("*")
    .eq("organization_id", orgId)
    .eq("id", contactId)
    .maybeSingle()
  return data
}

export async function getContactByPhone(client: SupabaseClient, phone: string, orgId = ORGANIZATION_ID) {
  const digits = phone.replace(/\D/g, "").slice(-10)
  const { data } = await client
    .from("contacts")
    .select("*")
    .eq("organization_id", orgId)
    .ilike("phone", `%${digits}%`)
    .limit(1)
    .maybeSingle()
  return data
}

export async function listTimeline(client: SupabaseClient, contactId: string) {
  const { data } = await client
    .from("contact_timeline")
    .select("*")
    .eq("contact_id", contactId)
    .order("at", { ascending: false })
  return data ?? []
}

export async function addTimeline(
  client: SupabaseClient,
  input: { contactId: string; label: string; detail?: string | null; kind: string; at?: string }
) {
  await client.from("contact_timeline").insert({
    id: `tl_${crypto.randomUUID()}`,
    organization_id: ORGANIZATION_ID,
    contact_id: input.contactId,
    label: input.label,
    detail: input.detail ?? null,
    kind: input.kind,
    at: input.at ?? new Date().toISOString(),
  })
}

export async function listCalls(client: SupabaseClient, orgId = ORGANIZATION_ID) {
  const { data, error } = await client
    .from("calls")
    .select("*")
    .eq("organization_id", orgId)
    .order("started_at", { ascending: false })
  if (error) throw new ApiError("server_error", 500, "We couldn't load your calls.")
  return data ?? []
}

export async function getCall(client: SupabaseClient, callId: string, orgId = ORGANIZATION_ID) {
  const { data } = await client
    .from("calls")
    .select("*")
    .eq("organization_id", orgId)
    .eq("id", callId)
    .maybeSingle()
  return data
}

export async function getTranscript(client: SupabaseClient, callId: string) {
  const { data } = await client
    .from("call_transcripts")
    .select("*")
    .eq("call_id", callId)
    .order("seq", { ascending: true })
  return data ?? []
}

export async function listFollowUps(client: SupabaseClient, orgId = ORGANIZATION_ID) {
  const { data } = await client
    .from("follow_ups")
    .select("*")
    .eq("organization_id", orgId)
    .order("date_time", { ascending: true })
  return data ?? []
}

export async function listCampaigns(client: SupabaseClient, orgId = ORGANIZATION_ID) {
  const { data } = await client
    .from("campaigns")
    .select("*")
    .eq("organization_id", orgId)
    .order("created_at", { ascending: false })
  return data ?? []
}

export async function getCampaign(client: SupabaseClient, campaignId: string, orgId = ORGANIZATION_ID) {
  const { data } = await client
    .from("campaigns")
    .select("*")
    .eq("organization_id", orgId)
    .eq("id", campaignId)
    .maybeSingle()
  return data
}

export async function campaignContactIds(client: SupabaseClient, campaignId: string) {
  const { data } = await client
    .from("campaign_contacts")
    .select("contact_id")
    .eq("campaign_id", campaignId)
  return (data ?? []).map((row) => row.contact_id as string)
}

/**
 * Records a provider webhook for idempotency. Returns false when this event has
 * already been received, which is how we ignore redeliveries.
 */
export async function recordWebhookEvent(
  client: SupabaseClient,
  input: {
    eventType: string
    providerEventId: string | null
    signatureValid: boolean
    payload: unknown
    organizationId?: string | null
  }
): Promise<{ duplicate: boolean; id: string }> {
  const id = `wh_${crypto.randomUUID()}`
  const { error } = await client.from("webhook_events").insert({
    id,
    organization_id: input.organizationId ?? null,
    provider: "sarvam",
    event_type: input.eventType,
    provider_event_id: input.providerEventId,
    signature_valid: input.signatureValid,
    payload: input.payload,
    status: "received",
  })

  if (error) {
    // 23505 = unique violation on provider_event_id: a redelivery we already have.
    if ((error as { code?: string }).code === "23505") return { duplicate: true, id }
    throw new ApiError("server_error", 500, "We couldn't record the call event.")
  }
  return { duplicate: false, id }
}

export async function finishWebhookEvent(
  client: SupabaseClient,
  id: string,
  status: "processed" | "ignored" | "failed",
  error?: string
) {
  await client
    .from("webhook_events")
    .update({ status, error: error ?? null, processed_at: new Date().toISOString() })
    .eq("id", id)
}

/**
 * Applies a finished call to the customer, call row, follow-up queue and
 * campaign counters in one place. This is the single write path shared by the
 * webhook handler and the in-app "complete call" action, so the Pipeline can
 * never drift from the call record.
 */
export async function applyCallResult(
  client: SupabaseClient,
  input: {
    callId: string
    contactId: string
    campaignId: string | null
    status: ContactStatusValue
    outcome: NormalisedOutcome
    result: StructuredAgentResult
    summary: string
    insight: string
    endedAt: string
    durationSeconds: number
  }
) {
  const { contactId, result } = input
  const followUpAt = result.followUpDate
    ? new Date(result.followUpDate).toISOString()
    : result.followUpRequired
      ? new Date(Date.now() + 86_400_000).toISOString()
      : null

  await client
    .from("calls")
    .update({
      status: input.status === "noResponse" ? "missed" : "completed",
      outcome: input.outcome,
      ended_at: input.endedAt,
      duration_seconds: input.durationSeconds,
      summary: input.summary,
      insight: input.insight,
    })
    .eq("id", input.callId)
    .eq("organization_id", ORGANIZATION_ID)

  await client
    .from("contacts")
    .update({
      status: input.status,
      last_call_at: input.endedAt,
      last_call_outcome: outcomeLabel(input.outcome),
      next_follow_up_at: followUpAt,
      ...(result.appointment ? { appointment: result.appointment } : {}),
      ...(result.amountRecovered !== null ? { recovered_amount: result.amountRecovered } : {}),
      ...(result.notes ? { notes: result.notes } : {}),
    })
    .eq("id", contactId)
    .eq("organization_id", ORGANIZATION_ID)

  await addTimeline(client, {
    contactId,
    label: outcomeLabel(input.outcome),
    detail: input.summary,
    kind: result.appointment ? "appointment" : "status",
    at: input.endedAt,
  })

  if (result.appointment) {
    await addTimeline(client, {
      contactId,
      label: "Appointment booked",
      detail: `${result.appointment.service || "Appointment"} at ${result.appointment.time}`,
      kind: "appointment",
      at: input.endedAt,
    })
  }

  if (followUpAt) {
    await client.from("follow_ups").insert({
      id: `f_${crypto.randomUUID()}`,
      organization_id: ORGANIZATION_ID,
      contact_id: contactId,
      date_time: followUpAt,
      type: result.appointment ? "reminder" : input.outcome === "noResponse" ? "whatsapp" : "call",
      status: "pending",
      message: result.notes || defaultFollowUpMessage(input.outcome),
    })
  }

  if (input.campaignId) {
    await bumpCampaignCounters(client, input.campaignId, input.outcome)
    await client
      .from("campaign_contacts")
      .update({ status: "completed" })
      .eq("campaign_id", input.campaignId)
      .eq("contact_id", contactId)
  }

}

function defaultFollowUpMessage(outcome: NormalisedOutcome): string {
  switch (outcome) {
    case "booked":
      return "Confirm the appointment closer to the date."
    case "noResponse":
      return "Send a WhatsApp message since the call was not answered."
    case "interested":
      return "Check if the customer is ready for the next step."
    default:
      return "Follow up with the customer."
  }
}

async function bumpCampaignCounters(
  client: SupabaseClient,
  campaignId: string,
  outcome: NormalisedOutcome
) {
  const { data } = await client
    .from("campaigns")
    .select("completed, booked, interested, follow_ups, no_answer, total")
    .eq("id", campaignId)
    .maybeSingle()
  if (!data) return

  const completed = data.completed + 1
  const patch: Record<string, number | string | null> = {
    completed,
    booked: data.booked + (outcome === "booked" ? 1 : 0),
    interested: data.interested + (outcome === "interested" ? 1 : 0),
    follow_ups: data.follow_ups + (outcome === "followUp" || outcome === "interested" ? 1 : 0),
    no_answer: data.no_answer + (outcome === "noResponse" ? 1 : 0),
  }
  if (completed >= data.total) patch.status = "completed"
  if (completed >= data.total) patch.ended_at = new Date().toISOString()

  await client.from("campaigns").update(patch).eq("id", campaignId).eq("organization_id", ORGANIZATION_ID)
}

export function outcomeLabel(outcome: NormalisedOutcome): string {
  switch (outcome) {
    case "booked":
      return "Appointment booked"
    case "recovered":
      return "Payment recovered"
    case "interested":
      return "Interested"
    case "followUp":
      return "Follow-up needed"
    case "notInterested":
      return "Not interested"
    case "noResponse":
      return "No answer"
  }
}
