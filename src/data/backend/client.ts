/**
 * The only channel between the app and the outside world.
 *
 * Every request goes to our own backend (`/functions/v1/api/...`). The backend
 * holds the voice provider credentials and talks to Sarvam on our behalf, so no
 * provider secret is ever present in this bundle.
 */

const BASE = `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/api`

/** A failure we can show the user as-is. `message` is already plain language. */
export class BackendError extends Error {
  readonly code: string
  readonly status: number

  constructor(code: string, message: string, status: number) {
    super(message)
    this.name = "BackendError"
    this.code = code
    this.status = status
  }
}

type RequestOptions = {
  method?: "GET" | "POST" | "PATCH"
  body?: unknown
  signal?: AbortSignal
}

async function request<T>(path: string, options: RequestOptions = {}): Promise<T> {
  const headers: Record<string, string> = {
    Authorization: `Bearer ${import.meta.env.VITE_SUPABASE_ANON_KEY}`,
  }
  if (options.body !== undefined) headers["Content-Type"] = "application/json"

  let response: Response
  try {
    response = await fetch(`${BASE}/${path}`, {
      method: options.method ?? "GET",
      headers,
      body: options.body === undefined ? undefined : JSON.stringify(options.body),
      signal: options.signal,
    })
  } catch (cause) {
    // A network failure is never surfaced raw; the user sees a calm message.
    throw new BackendError(
      "network",
      "We couldn't reach your AI right now. Check your connection and try again.",
      0
    )
  }

  const text = await response.text()
  let parsed: unknown = null
  try {
    parsed = text ? JSON.parse(text) : null
  } catch {
    parsed = null
  }

  if (!response.ok) {
    const errorBody = parsed as { error?: { code?: string; message?: string } } | null
    throw new BackendError(
      errorBody?.error?.code ?? "server_error",
      errorBody?.error?.message ?? "Something went wrong. Please try again.",
      response.status
    )
  }

  if (parsed === null) {
    throw new BackendError("bad_response", "We got an unexpected reply. Please try again.", response.status)
  }

  return parsed as T
}

export const backend = {
  bootstrap: () => request<import("./types").BootstrapPayload>("bootstrap"),
  phoneNumbers: () => request<import("./types").PhoneNumbersPayload>("phone-numbers"),
  aiAgent: () => request<import("./types").AgentPayload>("ai-agent"),
  updateAgent: (patch: Record<string, unknown>) =>
    request<import("./types").AgentPayload>("ai-agent", { method: "PATCH", body: patch }),

  startOutboundCall: (input: { contactId?: string; phone?: string; campaignId?: string }) =>
    request<{ callId: string; mode: string }>("calls/outbound", { method: "POST", body: input }),
  completeCall: (input: {
    callId: string
    outcome: string
    summary?: string
    insight?: string
    appointmentDate?: string
    amountRecovered?: number
    notes?: string
  }) => request<{ callId: string; outcome: string; status: string }>("calls/complete", { method: "POST", body: input }),
  transcript: (callId: string) =>
    request<import("./types").TranscriptPayload>(`calls/transcript?id=${encodeURIComponent(callId)}`),

  createCampaign: (input: { contactIds: string[]; purpose: string; scheduledFor?: string | null }) =>
    request<{ campaignId: string; mode: string }>("campaigns", { method: "POST", body: input }),
  advanceCampaign: (campaignId: string) =>
    request<{ campaign: import("./types").CampaignRow; mode: string }>("campaigns/step", {
      method: "POST",
      body: { campaignId },
    }),
  stopCampaign: (campaignId: string) =>
    request<{ campaign: import("./types").CampaignRow }>("campaigns/stop", {
      method: "POST",
      body: { campaignId },
    }),

  createContact: (input: { name: string; phone: string; service: string }) =>
    request<{ contact: import("./types").ContactRow }>("contacts", { method: "POST", body: input }),
  updateContact: (
    contactId: string,
    patch: { name?: string; phone?: string; service?: string; notes?: string }
  ) =>
    request<{ contact: import("./types").ContactRow }>("contacts/detail", {
      method: "PATCH",
      body: { contactId, ...patch },
    }),

  markFollowUpDone: (followUpId: string) =>
    request<{ followUpId: string }>("follow-ups/done", { method: "POST", body: { followUpId } }),
}
