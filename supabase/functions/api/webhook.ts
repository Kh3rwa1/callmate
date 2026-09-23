import {
  addTimeline,
  applyCallResult,
  db,
  finishWebhookEvent,
  getCall,
  getCampaign,
  getContactByPhone,
  getOrgConfig,
  recordWebhookEvent,
} from "./repo.ts"
import { errorResponse, json, preflight } from "./_http.ts"
import { log, logError } from "./_log.ts"
import { mapAgentResult, statusForOutcome } from "./voice/outcome.ts"

/**
 * Sarvam call/campaign event webhook.
 *
 * Sarvam POSTs here after every call attempt completes — connected or not — so
 * the Pipeline can move without the app polling. Two things make this safe:
 *
 *  1. Verification. Requests must carry either a valid HMAC-SHA256 signature of
 *     the raw body (`SARVAM_WEBHOOK_SECRET`) or the shared bearer token. When no
 *     secret is configured the event is recorded but marked unverified and NOT
 *     applied, so an unauthenticated caller can never move a customer's status.
 *     The verification mechanism is isolated here so it can be swapped for
 *     whatever the Sarvam dashboard issues without touching the rest of the flow.
 *
 *  2. Idempotency. Each attempt id is claimed in `webhook_events` (unique
 *     constraint) before any business write, so a redelivery is recognised and
 *     ignored instead of double-counting a call.
 *
 * Outcome determination reads the agent's structured variables first; the
 * transcript is stored for the Call Details screen but is not the source of
 * truth for the business outcome.
 */
export async function handleWebhook(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return preflight()

  const raw = await req.text()
  let payload: Record<string, unknown>
  try {
    payload = JSON.parse(raw) as Record<string, unknown>
  } catch {
    return json({ error: { code: "bad_request", message: "We couldn't read that event." } }, 400)
  }

  const client = db()
  const attempt = extractAttempt(payload)
  const signatureValid = verifySignature(req, raw)

  let eventRecordId: string | null = null
  try {
    const recorded = await recordWebhookEvent(client, {
      eventType: attempt.eventType,
      providerEventId: attempt.providerEventId,
      signatureValid,
      payload,
    })
    eventRecordId = recorded.id

    if (recorded.duplicate) {
      log("webhook_duplicate_ignored", {
        organization: attempt.organizationId,
        providerRequestId: attempt.providerEventId,
        eventType: attempt.eventType,
      })
      return json({ received: true, duplicate: true })
    }

    if (!signatureValid) {
      await finishWebhookEvent(client, recorded.id, "ignored", "signature_verification_failed")
      log("webhook_rejected_unverified", {
        organization: attempt.organizationId,
        providerRequestId: attempt.providerEventId,
        success: false,
      })
      // Accepted for recording, but nothing was applied.
      return json({ received: true, applied: false, reason: "unverified" }, 202)
    }

    const applied = await applyEvent(payload, attempt)
    await finishWebhookEvent(client, recorded.id, applied.applied ? "processed" : "ignored", applied.reason)

    log("webhook_processed", {
      organization: attempt.organizationId,
      providerRequestId: attempt.providerEventId,
      callId: applied.callId,
      campaignId: attempt.campaignId,
      eventType: attempt.eventType,
      outcome: applied.outcome,
      success: true,
    })

    return json({ received: true, applied: applied.applied, callId: applied.callId })
  } catch (error) {
    if (eventRecordId) await finishWebhookEvent(client, eventRecordId, "failed", String(error))
    logError("webhook_failed", error, {
      organization: attempt.organizationId,
      providerRequestId: attempt.providerEventId,
      success: false,
    })
    return errorResponse(error)
  }
}

type Attempt = {
  eventType: string
  providerEventId: string | null
  organizationId: string | null
  campaignId: string | null
  attemptId: string | null
  callId: string | null
  phone: string | null
  status: string
  deploymentId: string | null
  appVersion: number | null
  startedAt: string | null
  endedAt: string | null
  durationSeconds: number | null
  transcript: string | null
  summary: string | null
  agentVariables: Record<string, unknown> | null
  metadata: Record<string, unknown>
}

/**
 * Reads the documented Sarvam webhook fields. Field names follow the campaign,
 * instant-outbound and deployment payload references; where the provider nests
 * the same value under an alternative key we accept both rather than fail.
 */
function extractAttempt(payload: Record<string, unknown>): Attempt {
  const data = (payload.data as Record<string, unknown> | undefined) ?? payload
  const outbound = (data.outbound as Record<string, unknown> | undefined) ?? {}
  const userConfig = (data.user_config as Record<string, unknown> | undefined) ?? {}
  const appConfig = (data.app_config as Record<string, unknown> | undefined) ?? {}

  const metadata =
    ((data.metadata as Record<string, unknown> | undefined) ??
      (outbound.metadata as Record<string, unknown> | undefined) ??
      {}) as Record<string, unknown>

  const attemptId = str(
    data.attempt_id ?? outbound.attempt_id ?? data.id ?? (payload.attempt_id as string | undefined)
  )

  return {
    eventType: str(payload.event ?? payload.event_type ?? payload.type ?? "call.completed") ?? "call.completed",
    providerEventId: attemptId,
    organizationId:
      str(metadata.organizationId ?? metadata.organization_id ?? data.organization_id) ?? null,
    campaignId: str(metadata.campaignId ?? metadata.campaign_id ?? data.campaign_id) ?? null,
    attemptId,
    callId: str(metadata.callId ?? metadata.call_id) ?? null,
    phone: str(
      userConfig.user_phone_number ??
        data.user_phone_number ??
        data.phone_number ??
        outbound.user_phone_number
    ) ?? null,
    status: (str(data.call_status ?? data.status ?? outbound.status) ?? "completed").toLowerCase(),
    deploymentId: str(appConfig.app_id ?? data.app_id ?? data.deployment_id) ?? null,
    appVersion: num(appConfig.app_version ?? data.app_version) ?? null,
    startedAt: str(data.start_datetime ?? data.started_at ?? outbound.start_datetime) ?? null,
    endedAt: str(data.end_datetime ?? data.ended_at ?? outbound.end_datetime) ?? null,
    durationSeconds: num(data.duration ?? data.duration_seconds ?? outbound.duration) ?? null,
    transcript: str(data.transcript ?? data.output_transcript) ?? null,
    summary: str(data.summary ?? data.call_summary ?? data.output_summary) ?? null,
    agentVariables:
      (data.output_agent_variables as Record<string, unknown> | undefined) ??
      (data.agent_variables as Record<string, unknown> | undefined) ??
      null,
    metadata,
  }
}

function str(value: unknown): string | null {
  if (typeof value === "string" && value.trim() !== "") return value.trim()
  if (typeof value === "number") return String(value)
  return null
}

function num(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value
  if (typeof value === "string" && value.trim() !== "" && !Number.isNaN(Number(value))) return Number(value)
  return null
}

async function applyEvent(
  payload: Record<string, unknown>,
  attempt: Attempt
): Promise<{ applied: boolean; reason?: string; callId?: string; outcome?: string }> {
  const client = db()

  // Match the event to one of our calls: by our own call id from metadata, then
  // by the provider attempt id, then by customer phone as a last resort.
  let call = attempt.callId ? await getCall(client, attempt.callId) : null
  if (!call && attempt.attemptId) {
    const { data } = await client
      .from("calls")
      .select("*")
      .eq("sarvam_attempt_id", attempt.attemptId)
      .maybeSingle()
    call = data
  }
  if (!call && attempt.phone) {
    const contact = await getContactByPhone(client, attempt.phone)
    if (contact) {
      const { data } = await client
        .from("calls")
        .select("*")
        .eq("contact_id", contact.id)
        .in("status", ["calling", "connected"])
        .order("started_at", { ascending: false })
        .limit(1)
        .maybeSingle()
      call = data
    }
  }

  if (!call) return { applied: false, reason: "no_matching_call" }

  const org = await getOrgConfig(client)
  if (attempt.organizationId && attempt.organizationId !== org.id) {
    // A webhook carrying another tenant's id must never touch our data.
    return { applied: false, reason: "organization_mismatch" }
  }

  const endedAt = attempt.endedAt ?? new Date().toISOString()
  const startedAt = attempt.startedAt ?? call.started_at
  const duration =
    attempt.durationSeconds ??
    Math.max(0, Math.round((Date.parse(endedAt) - Date.parse(startedAt)) / 1000))

  // A call that never connected is an outcome in its own right.
  const connected = !/no_?answer|not_?connected|failed|busy|unanswered|cancel/.test(attempt.status)

  const result = mapAgentResult(
    attempt.agentVariables,
    [attempt.summary, attempt.transcript].filter(Boolean).join(" ")
  )

  const normalised = connected
    ? result
    : { ...result, outcome: "noResponse" as const, appointment: null, amountRecovered: null }

  await applyCallResult(client, {
    callId: call.id,
    contactId: call.contact_id,
    campaignId: call.campaign_id ?? attempt.campaignId,
    status: statusForOutcome(normalised.outcome),
    outcome: normalised.outcome,
    result: normalised,
    summary: attempt.summary ?? defaultSummaryFor(normalised.outcome),
    insight: normalised.customerIntent,
    endedAt,
    durationSeconds: duration,
  })

  // Provider identifiers, timings and the raw structured variables are kept on
  // the call for audit and for the Call Details screen.
  await client
    .from("calls")
    .update({
      sarvam_call_id: str(payload.call_id ?? attempt.metadata.callId) ?? null,
      deployment_id: attempt.deploymentId ?? call.deployment_id,
      agent_version: attempt.appVersion ?? call.agent_version,
      agent_variables: attempt.agentVariables,
      metadata: { ...attempt.metadata, provider: "sarvam", rawStatus: attempt.status },
    })
    .eq("id", call.id)

  // Transcript is stored separately so the Calls list never has to load it.
  if (attempt.transcript) {
    await storeTranscript(client, call.id, attempt.transcript, endedAt, org.id)
  }

  if (attempt.campaignId && !call.campaign_id) {
    await getCampaign(client, attempt.campaignId)
  }

  return { applied: true, callId: call.id, outcome: normalised.outcome }
}

/**
 * Splits a transcript into turns. Sarvam returns the conversation as text; we
 * detect speaker labels when present and otherwise store it as a single block so
 * nothing is invented or lost.
 */
async function storeTranscript(
  client: ReturnType<typeof db>,
  callId: string,
  transcript: string,
  at: string,
  organizationId: string
) {
  const { data: existing } = await client
    .from("call_transcripts")
    .select("id")
    .eq("call_id", callId)
    .limit(1)

  if (existing && existing.length > 0) return

  const lines = transcript
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)

  const rows = lines.map((line, index) => {
    const match = line.match(/^(agent|ai|assistant|bot|customer|user|caller)\s*[:\-]\s*(.+)$/i)
    const speakerTag = match?.[1]?.toLowerCase()
    const speaker = speakerTag
      ? ["customer", "user", "caller"].includes(speakerTag)
        ? "customer"
        : "ai"
      : "ai"
    return {
      id: `tr_${crypto.randomUUID()}`,
      organization_id: organizationId,
      call_id: callId,
      seq: index,
      speaker,
      text: match?.[2] ?? line,
      at,
    }
  })

  if (rows.length > 0) await client.from("call_transcripts").insert(rows)
}

function defaultSummaryFor(outcome: string): string {
  switch (outcome) {
    case "booked":
      return "Appointment booked on the call."
    case "recovered":
      return "Payment recovered on the call."
    case "interested":
      return "Customer is interested."
    case "followUp":
      return "Follow-up needed."
    case "notInterested":
      return "Customer is not interested."
    default:
      return "The customer did not answer."
  }
}

/**
 * Verifies the request. Supports the shared-secret bearer token and an
 * HMAC-SHA256 signature of the raw body, which is the standard delivery
 * assurance for provider webhooks. Returns false when nothing is configured, so
 * an unauthenticated request can never move data.
 */
function verifySignature(req: Request, raw: string): boolean {
  const secret = Deno.env.get("SARVAM_WEBHOOK_SECRET")
  if (!secret) return false

  const auth = req.headers.get("authorization") ?? ""
  if (auth === `Bearer ${secret}`) return true

  const provided =
    req.headers.get("x-sarvam-signature") ??
    req.headers.get("x-webhook-signature") ??
    req.headers.get("x-signature")

  if (!provided) return false

  const expected = hmacSha256Hex(secret, raw).toLowerCase()
  const normalised = provided.replace(/^sha256=/, "").toLowerCase()
  return timingSafeEqual(expected, normalised)
}

function hmacSha256Hex(secret: string, body: string): string {
  const key = new TextEncoder().encode(secret)
  const message = new TextEncoder().encode(body)
  // Synchronous HMAC is not available in the edge runtime, so we compute it
  // through a small pure-JS SHA-256 implementation.
  return hmacSha256(key, message)
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false
  let diff = 0
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i)
  return diff === 0
}

// --- minimal HMAC-SHA256 (no external dependency, works in the edge runtime) ---

function hmacSha256(key: Uint8Array, message: Uint8Array): string {
  const blockSize = 64
  let k = key
  if (k.length > blockSize) k = sha256(k)
  const padded = new Uint8Array(blockSize)
  padded.set(k)

  const inner = new Uint8Array(blockSize + message.length)
  const outer = new Uint8Array(blockSize + 32)
  for (let i = 0; i < blockSize; i++) {
    inner[i] = padded[i] ^ 0x36
    outer[i] = padded[i] ^ 0x5c
  }
  inner.set(message, blockSize)
  outer.set(sha256(inner), blockSize)
  return toHex(sha256(outer))
}

const K = new Uint32Array([
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
])

function sha256(data: Uint8Array): Uint8Array {
  const H = new Uint32Array([
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  ])

  const bitLen = data.length * 8
  const withPad = new Uint8Array((((data.length + 9) >> 6) + 1) << 6)
  withPad.set(data)
  withPad[data.length] = 0x80
  const view = new DataView(withPad.buffer)
  view.setUint32(withPad.length - 4, bitLen >>> 0)
  view.setUint32(withPad.length - 8, Math.floor(bitLen / 0x100000000))

  const w = new Uint32Array(64)
  for (let offset = 0; offset < withPad.length; offset += 64) {
    for (let i = 0; i < 16; i++) w[i] = view.getUint32(offset + i * 4)
    for (let i = 16; i < 64; i++) {
      const s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3)
      const s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10)
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) >>> 0
    }

    let [a, b, c, d, e, f, g, h] = H
    for (let i = 0; i < 64; i++) {
      const S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
      const ch = (e & f) ^ (~e & g)
      const t1 = (h + S1 + ch + K[i] + w[i]) >>> 0
      const S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
      const maj = (a & b) ^ (a & c) ^ (b & c)
      const t2 = (S0 + maj) >>> 0
      h = g; g = f; f = e; e = (d + t1) >>> 0
      d = c; c = b; b = a; a = (t1 + t2) >>> 0
    }

    H[0] = (H[0] + a) >>> 0; H[1] = (H[1] + b) >>> 0; H[2] = (H[2] + c) >>> 0; H[3] = (H[3] + d) >>> 0
    H[4] = (H[4] + e) >>> 0; H[5] = (H[5] + f) >>> 0; H[6] = (H[6] + g) >>> 0; H[7] = (H[7] + h) >>> 0
  }

  const out = new Uint8Array(32)
  const outView = new DataView(out.buffer)
  H.forEach((value, i) => outView.setUint32(i * 4, value))
  return out
}

function rotr(value: number, bits: number): number {
  return ((value >>> bits) | (value << (32 - bits))) >>> 0
}

function toHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("")
}
