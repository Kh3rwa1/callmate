import { applyCallResult, db, getCall, getCampaign } from "./repo.ts"
import { mapAgentResult, statusForOutcome, type NormalisedOutcome } from "./voice/outcome.ts"

/**
 * MOCK mode.
 *
 * Before a tenant has real Sarvam credentials (`voice_mode = 'mock'`), the
 * calling round still needs to behave end to end: the app asks the backend to
 * advance the round, and the backend writes the same records a real webhook
 * would. The screens, the Pipeline synchronisation and the follow-up queue are
 * therefore identical in both modes — only the source of the result differs.
 *
 * The simulated outcome is heavily weighted toward ordinary results so the demo
 * looks believable rather than always booking.
 */
const WEIGHTED: NormalisedOutcome[] = [
  "booked",
  "noResponse",
  "followUp",
  "interested",
  "booked",
  "noResponse",
  "recovered",
  "interested",
  "notInterested",
  "followUp",
  "recovered",
  "notInterested",
]

export async function simulateCampaignStep(campaignId: string): Promise<{
  callId: string
  outcome: NormalisedOutcome
} | null> {
  const client = db()
  const campaign = await getCampaign(client, campaignId)
  if (!campaign || campaign.status !== "running") return null

  const { data: pending } = await client
    .from("campaign_contacts")
    .select("contact_id")
    .eq("campaign_id", campaignId)
    .eq("status", "pending")
    .limit(1)

  const next = pending?.[0]
  if (!next) {
    await client.from("campaigns").update({ status: "completed", ended_at: new Date().toISOString() }).eq("id", campaignId)
    return null
  }

  const { data: contact } = await client
    .from("contacts")
    .select("*")
    .eq("id", next.contact_id)
    .maybeSingle()
  if (!contact) return null

  const { data: agent } = await client
    .from("ai_agents")
    .select("*")
    .eq("organization_id", campaign.organization_id)
    .maybeSingle()

  const outcome = WEIGHTED[Math.floor(Math.random() * WEIGHTED.length)]
  const callId = `call_${crypto.randomUUID()}`
  const startedAt = new Date(Date.now() - 142_000).toISOString()

  await client.from("contact_timeline").insert({
    id: `tl_${crypto.randomUUID()}`,
    organization_id: campaign.organization_id,
    contact_id: contact.id,
    label: "Shampy called",
    detail: "Outbound call from a calling round",
    kind: "call",
    at: startedAt,
  })

  await client.from("calls").insert({
    id: callId,
    organization_id: campaign.organization_id,
    contact_id: contact.id,
    campaign_id: campaignId,
    direction: "outbound",
    status: "calling",
    started_at: startedAt,
    deployment_id: null,
    agent_version: null,
  })

  await client
    .from("campaign_contacts")
    .update({ status: "calling" })
    .eq("campaign_id", campaignId)
    .eq("contact_id", contact.id)

  const result = mapAgentResult(
    buildSimulatedVariables(outcome, contact),
    simulatedProse(outcome, String(contact.name), String(agent?.language ?? "Hindi"))
  )

  await applyCallResult(client, {
    callId,
    contactId: contact.id,
    campaignId,
    status: statusForOutcome(result.outcome),
    outcome: result.outcome,
    result,
    summary: simulatedProse(result.outcome, String(contact.name), String(agent?.language ?? "Hindi")),
    insight: result.customerIntent,
    endedAt: new Date().toISOString(),
    durationSeconds: 142,
  })

  // A transcript is stored so the Call Details screen has content in mock mode
  // too; it is kept out of the calls list exactly as in the real flow.
  await client.from("call_transcripts").insert(
    buildSimulatedTranscript(outcome, String(contact.name)).map((turn, index) => ({
      id: `tr_${crypto.randomUUID()}`,
      organization_id: campaign.organization_id,
      call_id: callId,
      seq: index,
      speaker: turn.speaker,
      text: turn.text,
      at: startedAt,
    }))
  )

  return { callId, outcome: result.outcome }
}

function buildSimulatedVariables(
  outcome: NormalisedOutcome,
  contact: Record<string, unknown>
): Record<string, unknown> {
  const day = new Date(Date.now() + 86_400_000).toISOString().slice(0, 10)
  return {
    outcome:
      outcome === "followUp"
        ? "follow_up"
        : outcome === "noResponse"
          ? "no_response"
          : outcome === "notInterested"
            ? "not_interested"
            : outcome,
    appointment_booked: outcome === "booked",
    appointment_date: outcome === "booked" ? day : null,
    appointment_time: outcome === "booked" ? "16:00" : null,
    follow_up_required: outcome === "followUp" || outcome === "interested",
    follow_up_date: null,
    payment_recovered: outcome === "recovered",
    amount_recovered: outcome === "recovered" ? 7500 : null,
    customer_intent: intentFor(outcome),
    notes: `Simulated outcome for ${String(contact.name)}.`,
  }
}

function intentFor(outcome: NormalisedOutcome): string {
  switch (outcome) {
    case "booked":
      return "Ready to book"
    case "recovered":
      return "Payment collected on call"
    case "interested":
      return "Warm lead"
    case "followUp":
      return "Needs a follow-up"
    case "notInterested":
      return "Not interested for now"
    case "noResponse":
      return "Could not be reached"
  }
}

function simulatedProse(outcome: NormalisedOutcome, name: string, language: string): string {
  const first = name.split(" ")[0]
  switch (outcome) {
    case "booked":
      return `${first} confirmed an appointment for tomorrow.`
    case "recovered":
      return `${first} cleared the pending amount during the call.`
    case "interested":
      return `${first} is interested and asked for more details.`
    case "followUp":
      return `${first} asked to be called back later.`
    case "notInterested":
      return `${first} is not interested right now.`
    case "noResponse":
      return `${first} did not answer the call.`
  }
}

function buildSimulatedTranscript(
  outcome: NormalisedOutcome,
  name: string
): Array<{ speaker: "ai" | "customer"; text: string }> {
  const first = name.split(" ")[0]
  const opening: Array<{ speaker: "ai" | "customer"; text: string }> = [
    { speaker: "ai", text: `Namaste ${first} ji, main Sunrise Dental Clinic se baat kar rahi hoon.` },
    { speaker: "customer", text: "Haan boliye." },
  ]

  if (outcome === "noResponse") {
    return [{ speaker: "ai", text: "The call was not answered. No conversation took place." }]
  }

  const closing: Record<NormalisedOutcome, Array<{ speaker: "ai" | "customer"; text: string }>> = {
    booked: [
      { speaker: "ai", text: "Main kal shaam 4 baje ka appointment note kar rahi hoon." },
      { speaker: "customer", text: "Theek hai, main aa jaunga." },
    ],
    recovered: [
      { speaker: "ai", text: "Aapka pending payment abhi clear ho sakta hai." },
      { speaker: "customer", text: "Main abhi UPI se kar deta hoon." },
    ],
    interested: [
      { speaker: "ai", text: "Main aapko details WhatsApp par bhej deti hoon." },
      { speaker: "customer", text: "Haan bhej dijiye." },
    ],
    followUp: [
      { speaker: "ai", text: "Main aapko baad me call karti hoon." },
      { speaker: "customer", text: "Ji, shaam ko call karna." },
    ],
    notInterested: [
      { speaker: "ai", text: "Koi baat nahi, aapka samay ke liye dhanyavaad." },
      { speaker: "customer", text: "Thank you." },
    ],
    noResponse: [],
  }

  return [...opening, ...closing[outcome]]
}

export async function getSimulatedCall(callId: string) {
  return getCall(db(), callId)
}
