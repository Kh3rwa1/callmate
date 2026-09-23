import { createClient } from "npm:@supabase/supabase-js@2"

import {
  ORGANIZATION_ID,
  addTimeline,
  applyCallResult,
  checkCredits,
  db,
  finishWebhookEvent,
  getAgentRow,
  getCall,
  getCampaign,
  getContact,
  getContactByPhone,
  getOrgConfig,
  getPhoneNumberRow,
  getTranscript,
  getUsageRow,
  listCampaigns,
  listCalls,
  listContacts,
  listFollowUps,
  listTimeline,
  recordWebhookEvent,
  requireDeployment,
} from "./repo.ts"
import { ApiError, errorResponse, json, preflight } from "./_http.ts"
import { log, logError } from "./_log.ts"
import { mapAgentResult, statusForOutcome } from "./voice/outcome.ts"
import type { NormalisedOutcome } from "./voice/outcome.ts"
import { ProviderError } from "./voice/types.ts"
import { resolveVoiceProvider, type OrgVoiceConfig } from "./voice/index.ts"
import { handleWebhook } from "./webhook.ts"
import { phoneIsValid, toCampaignInput, toOutboundInput } from "./payload.ts"
import { simulateCampaignStep } from "./simulate.ts"

/**
 * The single backend for the app.
 *
 * Route map (the function is mounted at /functions/v1/api, so the paths the app
 * calls are /api/... as documented in the product requirements):
 *   POST /api/calls/outbound
 *   POST /api/campaigns
 *   POST /api/campaigns/:id/start
 *   GET  /api/campaigns/:id
 *   POST /api/campaigns/:id/stop
 *   GET  /api/calls
 *   GET  /api/calls/:id
 *   GET  /api/calls/:id/transcript
 *   POST /api/calls/:id/complete
 *   GET  /api/phone-numbers
 *   GET  /api/ai-agent
 *   PATCH /api/ai-agent
 *   GET  /api/bootstrap
 *   POST /api/contacts
 *   POST /api/webhooks/sarvam
 *
 * This function is the only thing holding the Sarvam API key and the service role
 * key. Every query is scoped to ORGANIZATION_ID, so one tenant can never reach
 * another tenant's voice data.
 */

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return preflight()

  const url = new URL(req.url)
  const path = normalisePath(url.pathname)
  const method = req.method

  try {
    if (path === "webhooks/sarvam" && method === "POST") {
      return await handleWebhook(req)
    }

    if (method === "GET" && path === "bootstrap") return await bootstrap()
    if (method === "GET" && path === "phone-numbers") return await phoneNumbers()
    if (method === "GET" && path === "ai-agent") return await getAgent()
    if (method === "PATCH" && path === "ai-agent") return await updateAgent(req)

    if (method === "POST" && path === "calls/outbound") return await startOutboundCall(req)
    if (method === "GET" && path === "calls") return await calls()
    if (method === "POST" && path === "calls/complete") return await completeCall(req)
    if (method === "GET" && path === "calls/transcript") return await transcript(url)
    if (method === "GET" && path === "calls/detail") return await callDetail(url)

    if (method === "POST" && path === "campaigns") return await createCampaign(req)
    if (method === "GET" && path === "campaigns/detail") return await campaignDetail(url)
    if (method === "POST" && path === "campaigns/start") return await startCampaign(req)
    if (method === "POST" && path === "campaigns/stop") return await stopCampaign(req)
    if (method === "POST" && path === "campaigns/step") return await advanceCampaign(req)

    if (method === "POST" && path === "contacts") return await createContact(req)
    if (method === "PATCH" && path === "contacts/detail") return await updateContact(req)
    if (method === "POST" && path === "follow-ups/done") return await completeFollowUp(req)
    if (method === "GET" && path === "follow-ups") return await followUps()

    return json({ error: { code: "not_found", message: "That request isn't supported." } }, 404)
  } catch (error) {
    logError("api_request_failed", error, { path, method })
    return errorResponse(mapProviderError(error))
  }
})

/**
 * Strips the leading /functions/v1/<slug> (or /<slug>) prefix so routes are
 * matched the same whether called through Supabase or a direct host.
 */
function normalisePath(pathname: string): string {
  let path = pathname.replace(/^\/functions\/v1\/api/, "").replace(/^\/api/, "")
  path = path.replace(/^\/+/, "").replace(/\/+$/, "")
  return path
}

/** Provider failures are mapped to friendly, actionable messages. */
function mapProviderError(error: unknown): unknown {
  if (!(error instanceof ProviderError)) return error
  switch (error.kind) {
    case "timeout":
      return new ApiError(
        "provider_timeout",
        504,
        "Your AI couldn't start the call in time. Please try again.",
        error.message
      )
    case "auth":
      return new ApiError(
        "provider_auth",
        502,
        "Your calling service needs reconnecting. Check your voice service settings.",
        error.message
      )
    case "credits":
      return new ApiError(
        "insufficient_credits",
        402,
        "Your voice service account is out of credits. Top up to keep calling.",
        error.message
      )
    case "validation":
      return new ApiError(
        "provider_rejected",
        400,
        "Your AI couldn't start that call. Please check the customer's number and try again.",
        error.message
      )
    default:
      return new ApiError(
        "provider_unavailable",
        503,
        "Your AI couldn't start the call. Try again.",
        error.message
      )
  }
}

async function voiceContext() {
  const client = db()
  const org = await getOrgConfig(client)
  const config: OrgVoiceConfig = {
    sarvamOrgId: org.sarvamOrgId,
    sarvamWorkspaceId: org.sarvamWorkspaceId,
    sarvamDeploymentId: org.sarvamDeploymentId,
    sarvamAppVersion: org.sarvamAppVersion,
    voiceMode: org.voiceMode,
  }
  const provider = resolveVoiceProvider(config, { apiKey: Deno.env.get("SARVAM_API_KEY") ?? undefined })
  const phone = await getPhoneNumberRow(client)
  return { client, org, provider, phone }
}

function webhookUrl(req: Request): string {
  const url = new URL(req.url)
  url.pathname = url.pathname.replace(/\/[^/]*$/, "/webhooks/sarvam")
  return url.toString()
}

// ---------------------------------------------------------------------------
// Reads
// ---------------------------------------------------------------------------

async function bootstrap() {
  const { client, org, phone } = await voiceContext()
  const [contacts, calls, followUps, campaigns, agent, usage, membership] = await Promise.all([
    listContacts(client),
    listCalls(client),
    listFollowUps(client),
    listCampaigns(client),
    getAgentRow(client),
    getUsageRow(client),
    client.from("campaign_contacts").select("campaign_id, contact_id, status").eq("organization_id", ORGANIZATION_ID),
  ])

  const campaignContacts: Record<string, string[]> = {}
  for (const row of membership.data ?? []) {
    const key = row.campaign_id as string
    ;(campaignContacts[key] ??= []).push(row.contact_id as string)
  }

  const timeline = await Promise.all(
    contacts.map(async (contact: Record<string, unknown>) => ({
      contactId: contact.id as string,
      entries: await listTimeline(client, contact.id as string),
    }))
  )

  return json({
    organization: { id: org.id, name: org.name, voiceMode: org.voiceMode },
    phoneNumber: phone,
    agent,
    usage,
    contacts,
    calls,
    followUps,
    campaigns,
    campaignContacts,
    timeline: Object.fromEntries(timeline.map((t) => [t.contactId, t.entries])),
  })
}

async function phoneNumbers() {
  const { client, provider, phone } = await voiceContext()
  // When live, prefer the numbers actually registered with the provider.
  if (provider) {
    try {
      const numbers = await provider.getPhoneNumbers()
      if (numbers.length > 0) return json({ phoneNumber: phone, providerNumbers: numbers })
    } catch (error) {
      logError("provider_phone_numbers_failed", error)
    }
  }
  return json({ phoneNumber: phone, providerNumbers: [] })
}

async function getAgent() {
  const client = db()
  const [agent, phone] = await Promise.all([getAgentRow(client), getPhoneNumberRow(client)])
  return json({ agent, phoneNumber: phone })
}

async function updateAgent(req: Request) {
  const body = await req.json()
  const allowed = [
    "name",
    "language",
    "voice",
    "call_style",
    "working_hours_start",
    "working_hours_end",
    "follow_up_enabled",
    "follow_up_delay_days",
    "greeting",
    "inbound_enabled",
  ] as const

  const patch: Record<string, unknown> = { updated_at: new Date().toISOString() }
  for (const key of allowed) {
    if (key in body) patch[key] = body[key]
  }

  const client = db()
  const { error } = await client.from("ai_agents").update(patch).eq("organization_id", ORGANIZATION_ID)
  if (error) throw new ApiError("server_error", 500, "We couldn't save your AI employee settings.")

  log("agent_updated", { organization: ORGANIZATION_ID, fields: Object.keys(patch) })
  return json({ agent: await getAgentRow(client) })
}

async function calls() {
  const client = db()
  return json({ calls: await listCalls(client) })
}

async function callDetail(url: URL) {
  const id = url.searchParams.get("id")
  if (!id) throw new ApiError("bad_request", 400, "Which call would you like to see?")
  const client = db()
  const call = await getCall(client, id)
  if (!call) throw new ApiError("not_found", 404, "We couldn't find that call.")
  const contact = await getContact(client, call.contact_id)
  return json({ call, contact })
}

async function transcript(url: URL) {
  const id = url.searchParams.get("id")
  if (!id) throw new ApiError("bad_request", 400, "Which call would you like to see?")
  const client = db()
  const call = await getCall(client, id)
  if (!call) throw new ApiError("not_found", 404, "We couldn't find that call.")
  // Transcripts are only served by this dedicated endpoint and never on the list.
  return json({
    callId: id,
    summary: call.summary,
    outcome: call.outcome,
    duration: call.duration_seconds,
    turns: await getTranscript(client, id),
  })
}

// ---------------------------------------------------------------------------
// Writes
// ---------------------------------------------------------------------------

async function startOutboundCall(req: Request) {
  const body = await req.json().catch(() => ({}))
  const contactId = typeof body.contactId === "string" ? body.contactId : null
  const rawPhone = typeof body.phone === "string" ? body.phone : null
  const campaignId = typeof body.campaignId === "string" ? body.campaignId : null

  if (!phoneIsValid(rawPhone ?? "") && !contactId) {
    throw new ApiError("invalid_phone", 400, "That phone number doesn't look right. Please check and try again.")
  }

  const client = db()
  await checkCredits(client)

  const contact = contactId ? await getContact(client, contactId) : await getContactByPhone(client, rawPhone!)
  if (!contact) throw new ApiError("not_found", 404, "We couldn't find that customer.")
  if (!phoneIsValid(contact.phone)) {
    throw new ApiError("invalid_phone", 400, "That customer's phone number doesn't look right.")
  }

  const org = await getOrgConfig(client)
  const provider = resolveVoiceProvider(
    {
      sarvamOrgId: org.sarvamOrgId,
      sarvamWorkspaceId: org.sarvamWorkspaceId,
      sarvamDeploymentId: org.sarvamDeploymentId,
      sarvamAppVersion: org.sarvamAppVersion,
      voiceMode: org.voiceMode,
    },
    { apiKey: Deno.env.get("SARVAM_API_KEY") ?? undefined }
  )

  const phoneRow = await getPhoneNumberRow(client)
  const agentRow = await getAgentRow(client)
  const callId = `call_${crypto.randomUUID()}`

  // Our own record is created first so the call exists even if the provider call
  // fails — the failure is then attached to a real row instead of vanishing.
  const { error: insertError } = await client.from("calls").insert({
    id: callId,
    organization_id: ORGANIZATION_ID,
    contact_id: contact.id,
    campaign_id: campaignId,
    direction: "outbound",
    status: "calling",
    outcome: null,
    started_at: new Date().toISOString(),
    summary: "",
    insight: "",
    deployment_id: org.sarvamDeploymentId,
    agent_version: org.sarvamAppVersion,
  })
  if (insertError) throw new ApiError("server_error", 500, "We couldn't start that call. Please try again.")

  await client.from("contacts").update({ status: "calling" }).eq("id", contact.id)

  if (!provider) {
    // MOCK mode: nothing leaves our backend. The call sits in "calling" and is
    // resolved in-app, which is how the product works before Sarvam is connected.
    log("outbound_call_mock", { organization: ORGANIZATION_ID, callId, contactId: contact.id })
    return json({ callId, mode: "mock" })
  }

  try {
    const deploymentId = await requireDeployment(org)
    const { attemptId } = await provider.startOutboundCall(
      toOutboundInput({
        deploymentId,
        appVersion: org.sarvamAppVersion,
        contact,
        phone: phoneRow,
        agent: agentRow,
        webhookUrl: webhookUrl(req),
        callId,
      })
    )

    await client
      .from("calls")
      .update({ sarvam_attempt_id: attemptId, metadata: { provider: "sarvam" } })
      .eq("id", callId)

    log("outbound_call_started", {
      organization: ORGANIZATION_ID,
      callId,
      contactId: contact.id,
      providerRequestId: attemptId,
      success: true,
    })

    return json({ callId, attemptId, mode: "sarvam" })
  } catch (error) {
    await client
      .from("calls")
      .update({
        status: "failed",
        ended_at: new Date().toISOString(),
        summary: "We couldn't reach our calling service.",
      })
      .eq("id", callId)
    await client.from("contacts").update({ status: "noResponse" }).eq("id", contact.id)
    logError("outbound_call_failed", error, { organization: ORGANIZATION_ID, callId, success: false })
    throw error
  }
}

async function completeCall(req: Request) {
  const body = await req.json().catch(() => ({}))
  const callId = typeof body.callId === "string" ? body.callId : null
  const outcome = typeof body.outcome === "string" ? (body.outcome as NormalisedOutcome) : null
  if (!callId || !outcome) throw new ApiError("bad_request", 400, "That call couldn't be completed.")

  const client = db()
  const call = await getCall(client, callId)
  if (!call) throw new ApiError("not_found", 404, "We couldn't find that call.")

  const result = mapAgentResult(
    {
      outcome: outcome === "followUp" ? "follow_up" : outcome === "noResponse" ? "no_response" : outcome === "notInterested" ? "not_interested" : outcome,
      appointment_booked: outcome === "booked",
      appointment_date: typeof body.appointmentDate === "string" ? body.appointmentDate : null,
      follow_up_required: outcome === "followUp" || outcome === "interested",
      amount_recovered: typeof body.amountRecovered === "number" ? body.amountRecovered : null,
      notes: typeof body.notes === "string" ? body.notes : "",
    },
    typeof body.summary === "string" ? body.summary : ""
  )

  const endedAt = new Date().toISOString()
  const started = new Date(call.started_at).getTime()
  const duration = Math.max(0, Math.round((Date.parse(endedAt) - started) / 1000))

  await applyCallResult(client, {
    callId,
    contactId: call.contact_id,
    campaignId: call.campaign_id,
    status: statusForOutcome(result.outcome),
    outcome: result.outcome,
    result,
    summary: typeof body.summary === "string" && body.summary ? body.summary : defaultSummary(result.outcome),
    insight: typeof body.insight === "string" ? body.insight : "",
    endedAt,
    durationSeconds: duration,
  })

  log("call_completed_in_app", {
    organization: ORGANIZATION_ID,
    callId,
    outcome: result.outcome,
    success: true,
  })

  return json({ callId, outcome: result.outcome, status: statusForOutcome(result.outcome) })
}

function defaultSummary(outcome: NormalisedOutcome): string {
  switch (outcome) {
    case "booked":
      return "Appointment booked on the call."
    case "recovered":
      return "Payment recovered on the call."
    case "interested":
      return "Customer is interested and wants a follow-up."
    case "followUp":
      return "Follow-up needed."
    case "notInterested":
      return "Customer is not interested right now."
    case "noResponse":
      return "The customer did not answer."
  }
}

async function createCampaign(req: Request) {
  const body = await req.json().catch(() => ({}))
  const contactIds: string[] = Array.isArray(body.contactIds) ? body.contactIds : []
  const purpose = typeof body.purpose === "string" ? body.purpose : "other"
  const scheduledFor = typeof body.scheduledFor === "string" ? body.scheduledFor : null

  if (contactIds.length === 0) {
    throw new ApiError("bad_request", 400, "Choose at least one customer to call.")
  }

  const client = db()
  await checkCredits(client)
  const org = await getOrgConfig(client)
  const phoneRow = await getPhoneNumberRow(client)
  const agentRow = await getAgentRow(client)

  const provider = resolveVoiceProvider(
    {
      sarvamOrgId: org.sarvamOrgId,
      sarvamWorkspaceId: org.sarvamWorkspaceId,
      sarvamDeploymentId: org.sarvamDeploymentId,
      sarvamAppVersion: org.sarvamAppVersion,
      voiceMode: org.voiceMode,
    },
    { apiKey: Deno.env.get("SARVAM_API_KEY") ?? undefined }
  )

  const campaignId = `camp_${crypto.randomUUID()}`
  const startedAt = new Date().toISOString()

  const { error } = await client.from("campaigns").insert({
    id: campaignId,
    organization_id: ORGANIZATION_ID,
    name: "Calling round",
    purpose,
    status: "running",
    scheduled_for: scheduledFor,
    started_at: startedAt,
    total: contactIds.length,
  })
  if (error) throw new ApiError("server_error", 500, "We couldn't start that calling round.")

  await client.from("campaign_contacts").insert(
    contactIds.map((contactId) => ({
      campaign_id: campaignId,
      contact_id: contactId,
      organization_id: ORGANIZATION_ID,
      status: "pending",
    }))
  )

  if (!provider) {
    log("campaign_started_mock", { organization: ORGANIZATION_ID, campaignId, total: contactIds.length })
    return json({ campaignId, mode: "mock", campaign: await getCampaign(client, campaignId) })
  }

  try {
    const deploymentId = await requireDeployment(org)
    const contacts = await Promise.all(contactIds.map((id) => getContact(client, id)))
    const created = await provider.createCampaign(
      toCampaignInput({
        name: `Callmate round ${new Date().toLocaleDateString("en-IN")}`,
        deploymentId,
        appVersion: org.sarvamAppVersion,
        phone: phoneRow,
        agent: agentRow,
        webhookUrl: webhookUrl(req),
        campaignId,
        scheduledFor,
      })
    )

    await provider.uploadCohort({
      campaignId: created.campaignId,
      name: "Callmate cohort",
      csv: toCohortCsv(
        contacts.filter(Boolean).map((c) => ({
          phone: c!.phone,
          name: c!.name,
          contactId: c!.id,
          service: c!.service,
        }))
      ),
    })

    await provider.startCampaign(created.campaignId)

    await client
      .from("campaigns")
      .update({ sarvam_campaign_id: created.campaignId, status: "running" })
      .eq("id", campaignId)

    log("campaign_started", {
      organization: ORGANIZATION_ID,
      campaignId,
      providerCampaignId: created.campaignId,
      total: contactIds.length,
      success: true,
    })

    return json({ campaignId, mode: "sarvam", campaign: await getCampaign(client, campaignId) })
  } catch (error) {
    // The round exists but the provider refused it, so it is left as a draft the
    // user can retry rather than appearing to be running.
    await client.from("campaigns").update({ status: "draft" }).eq("id", campaignId)
    logError("campaign_start_failed", error, { organization: ORGANIZATION_ID, campaignId, success: false })
    throw error
  }
}

/**
 * Advances a calling round by one call. In MOCK mode this is how the round makes
 * progress; in SARVAM mode the provider calls customers itself and this returns
 * the current state without inventing anything.
 */
async function advanceCampaign(req: Request) {
  const body = await req.json().catch(() => ({}))
  const campaignId = typeof body.campaignId === "string" ? body.campaignId : null
  if (!campaignId) throw new ApiError("bad_request", 400, "Which calling round should continue?")

  const client = db()
  const org = await getOrgConfig(client)
  const campaign = await getCampaign(client, campaignId)
  if (!campaign) throw new ApiError("not_found", 404, "We couldn't find that calling round.")

  if (org.voiceMode === "sarvam" && campaign.sarvam_campaign_id) {
    // Real mode: the provider drives the calls and the webhook reports back.
    return json({ campaign: await getCampaign(client, campaignId), mode: "sarvam" })
  }

  const stepped = await simulateCampaignStep(campaignId)
  log("campaign_step", {
    organization: ORGANIZATION_ID,
    campaignId,
    callId: stepped?.callId,
    outcome: stepped?.outcome,
    success: true,
  })
  return json({ campaign: await getCampaign(client, campaignId), mode: "mock", step: stepped })
}

function toCohortCsv(
  rows: Array<{ phone: string; name: string; contactId: string; service: string }>
): string {
  const header = "phone_number,name,contact_id,service"
  const body = rows
    .map((row) => [row.phone, row.name, row.contactId, row.service].map(csvCell).join(","))
    .join("\n")
  return `${header}\n${body}\n`
}

function csvCell(value: string): string {
  const escaped = value.replace(/"/g, '""')
  return /[",\n]/.test(value) ? `"${escaped}"` : escaped
}

async function startCampaign(req: Request) {
  const body = await req.json().catch(() => ({}))
  const campaignId = typeof body.campaignId === "string" ? body.campaignId : null
  if (!campaignId) throw new ApiError("bad_request", 400, "Which calling round should start?")

  const client = db()
  const campaign = await getCampaign(client, campaignId)
  if (!campaign) throw new ApiError("not_found", 404, "We couldn't find that calling round.")

  const { provider } = await voiceContext()
  if (provider && campaign.sarvam_campaign_id) {
    await provider.startCampaign(campaign.sarvam_campaign_id)
  }
  await client.from("campaigns").update({ status: "running" }).eq("id", campaignId)
  return json({ campaign: await getCampaign(client, campaignId) })
}

async function stopCampaign(req: Request) {
  const body = await req.json().catch(() => ({}))
  const campaignId = typeof body.campaignId === "string" ? body.campaignId : null
  if (!campaignId) throw new ApiError("bad_request", 400, "Which calling round should stop?")

  const client = db()
  const campaign = await getCampaign(client, campaignId)
  if (!campaign) throw new ApiError("not_found", 404, "We couldn't find that calling round.")

  const { provider } = await voiceContext()
  if (provider && campaign.sarvam_campaign_id) {
    try {
      await provider.stopCampaign(campaign.sarvam_campaign_id)
    } catch (error) {
      logError("campaign_stop_failed", error, { campaignId })
    }
  }
  await client
    .from("campaigns")
    .update({ status: "stopped", ended_at: new Date().toISOString() })
    .eq("id", campaignId)

  log("campaign_stopped", { organization: ORGANIZATION_ID, campaignId, success: true })
  return json({ campaign: await getCampaign(client, campaignId) })
}

async function campaignDetail(url: URL) {
  const id = url.searchParams.get("id")
  if (!id) throw new ApiError("bad_request", 400, "Which calling round would you like to see?")
  const client = db()
  const campaign = await getCampaign(client, id)
  if (!campaign) throw new ApiError("not_found", 404, "We couldn't find that calling round.")
  return json({ campaign })
}

async function followUps() {
  const client = db()
  return json({ followUps: await listFollowUps(client) })
}

async function updateContact(req: Request) {
  const body = await req.json().catch(() => ({}))
  const contactId = typeof body.contactId === "string" ? body.contactId : null
  if (!contactId) throw new ApiError("bad_request", 400, "Which customer should be updated?")

  const patch: Record<string, unknown> = {}
  if (typeof body.name === "string" && body.name.trim()) patch.name = body.name.trim()
  if (typeof body.phone === "string" && body.phone.trim()) {
    if (!phoneIsValid(body.phone)) {
      throw new ApiError("invalid_phone", 400, "That phone number doesn't look right. Please check and try again.")
    }
    patch.phone = body.phone.trim()
  }
  if (typeof body.service === "string" && body.service.trim()) patch.service = body.service.trim()
  if (typeof body.notes === "string") patch.notes = body.notes

  if (Object.keys(patch).length === 0) {
    throw new ApiError("bad_request", 400, "There was nothing to update.")
  }

  const client = db()
  const contact = await getContact(client, contactId)
  if (!contact) throw new ApiError("not_found", 404, "We couldn't find that customer.")

  const { error } = await client.from("contacts").update(patch).eq("id", contactId).eq("organization_id", ORGANIZATION_ID)
  if (error) throw new ApiError("server_error", 500, "We couldn't save those changes.")

  await addTimeline(client, {
    contactId,
    label: "Details updated",
    detail: "You edited this customer",
    kind: "status",
  })

  log("contact_updated", { organization: ORGANIZATION_ID, contactId, success: true })
  return json({ contact: await getContact(client, contactId) })
}

async function completeFollowUp(req: Request) {
  const body = await req.json().catch(() => ({}))
  const followUpId = typeof body.followUpId === "string" ? body.followUpId : null
  if (!followUpId) throw new ApiError("bad_request", 400, "Which follow-up should be closed?")

  const client = db()
  const { error } = await client
    .from("follow_ups")
    .update({ status: "done" })
    .eq("id", followUpId)
    .eq("organization_id", ORGANIZATION_ID)
  if (error) throw new ApiError("server_error", 500, "We couldn't update that follow-up.")

  log("follow_up_completed", { organization: ORGANIZATION_ID, success: true })
  return json({ followUpId })
}

async function createContact(req: Request) {
  const body = await req.json().catch(() => ({}))
  const name = typeof body.name === "string" ? body.name.trim() : ""
  const phone = typeof body.phone === "string" ? body.phone.trim() : ""
  const service = typeof body.service === "string" && body.service.trim() ? body.service.trim() : "Enquiry"

  if (!name) throw new ApiError("bad_request", 400, "Please enter the customer's name.")
  if (!phoneIsValid(phone)) {
    throw new ApiError("invalid_phone", 400, "That phone number doesn't look right. Please check and try again.")
  }

  const client = db()
  const id = `c_${crypto.randomUUID()}`
  const palette = ["#18C97A", "#4C7DFF", "#8B5CF6", "#FF9F43", "#FF6B6B", "#22B8CF"]
  const color = palette[Math.floor(Math.random() * palette.length)]

  const { error } = await client.from("contacts").insert({
    id,
    organization_id: ORGANIZATION_ID,
    name,
    phone,
    avatar_color: color,
    service,
    status: "new",
    tags: ["New lead"],
    notes: "",
    source: "manual",
  })
  if (error) throw new ApiError("server_error", 500, "We couldn't add that customer. Please try again.")

  await addTimeline(client, {
    contactId: id,
    label: "Added to Callmate",
    detail: "Ready for the first call",
    kind: "created",
  })

  log("contact_created", { organization: ORGANIZATION_ID, contactId: id, success: true })
  return json({ contact: await getContact(client, id) })
}
