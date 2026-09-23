/**
 * Maps the structured fields a Sarvam agent returns into our own vocabulary.
 *
 * The agent is configured to report an explicit `outcome` plus booleans for the
 * things that matter to the business. We read those FIRST, and only fall back to
 * interpreting the summary text when the structured fields are absent — the
 * provider's own documentation notes the structured agent variables are the
 * reliable source, and a transcript can be ambiguous.
 */

export const PROVIDER_OUTCOMES = [
  "booked",
  "interested",
  "follow_up",
  "recovered",
  "not_interested",
  "no_response",
] as const

export type ProviderOutcome = (typeof PROVIDER_OUTCOMES)[number]

/** Our normalised outcome / contact status vocabulary. */
export type NormalisedOutcome = "booked" | "interested" | "followUp" | "recovered" | "notInterested" | "noResponse"

export type ContactStatusValue =
  | "new"
  | "calling"
  | "followUp"
  | "booked"
  | "recovered"
  | "noResponse"
  | "notInterested"

export type StructuredAgentResult = {
  outcome: NormalisedOutcome
  appointment: { date: string; time: string; service: string; status: "scheduled" } | null
  followUpRequired: boolean
  followUpDate: string | null
  paymentRecovered: boolean
  amountRecovered: number | null
  customerIntent: string
  notes: string
  /** True when we had to infer the outcome instead of reading it. */
  inferred: boolean
}

const OUTCOME_MAP: Record<ProviderOutcome, NormalisedOutcome> = {
  booked: "booked",
  interested: "interested",
  follow_up: "followUp",
  recovered: "recovered",
  not_interested: "notInterested",
  no_response: "noResponse",
}

/** Structured outcome -> the status shown on the Pipeline. */
export function statusForOutcome(outcome: NormalisedOutcome): ContactStatusValue {
  switch (outcome) {
    case "booked":
      return "booked"
    case "recovered":
      return "recovered"
    case "interested":
    case "followUp":
      return "followUp"
    case "notInterested":
      return "notInterested"
    case "noResponse":
      return "noResponse"
  }
}

function asString(value: unknown): string | null {
  if (typeof value === "string" && value.trim() !== "") return value.trim()
  return null
}

function asBoolean(value: unknown): boolean {
  if (typeof value === "boolean") return value
  if (typeof value === "string") return value.toLowerCase() === "true"
  return false
}

function asNumber(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value
  if (typeof value === "string" && value.trim() !== "" && !Number.isNaN(Number(value))) {
    return Number(value)
  }
  return null
}

function normaliseOutcome(raw: unknown): NormalisedOutcome | null {
  const value = asString(raw)
  if (!value) return null
  const key = value.toLowerCase().replace(/[\s-]+/g, "_") as ProviderOutcome
  return OUTCOME_MAP[key] ?? null
}

/**
 * Best-effort reading of prose, used only when the agent did not return an
 * explicit structured outcome. Deliberately conservative: when nothing matches
 * we report "no response" rather than inventing a positive result.
 */
function inferFromText(text: string): NormalisedOutcome {
  const t = text.toLowerCase()
  if (/book|appointment|schedul|confirm/.test(t)) return "booked"
  if (/recover|paid|payment received|cleared the (pending|due)/.test(t)) return "recovered"
  if (/not interested|declin|refus/.test(t)) return "notInterested"
  if (/follow ?up|call back|callback/.test(t)) return "followUp"
  if (/no answer|no response|didn'?t (pick|answer)|unreach|missed/.test(t)) return "noResponse"
  if (/interest|warm|keen|asked about/.test(t)) return "interested"
  return "noResponse"
}

export function mapAgentResult(
  variables: Record<string, unknown> | null | undefined,
  fallbackText: string
): StructuredAgentResult {
  const vars = variables ?? {}
  const explicit = normaliseOutcome(vars.outcome)
  const inferred = explicit === null
  const outcome = explicit ?? inferFromText(fallbackText)

  const date = asString(vars.appointment_date)
  const time = asString(vars.appointment_time)
  const appointmentBooked = asBoolean(vars.appointment_booked) || (outcome === "booked" && !!date)

  // An appointment is only recorded when the agent actually booked one and we
  // have a date to put on the calendar.
  const appointment =
    appointmentBooked && date
      ? { date, time: time ?? "10:00", service: asString(vars.service) ?? "", status: "scheduled" as const }
      : null

  const paymentRecovered = asBoolean(vars.payment_recovered) || outcome === "recovered"

  return {
    outcome,
    appointment,
    followUpRequired: asBoolean(vars.follow_up_required) || outcome === "followUp" || outcome === "interested",
    followUpDate: asString(vars.follow_up_date),
    paymentRecovered,
    amountRecovered: paymentRecovered ? asNumber(vars.amount_recovered) : null,
    customerIntent: asString(vars.customer_intent) ?? "",
    notes: asString(vars.notes) ?? "",
    inferred,
  }
}
