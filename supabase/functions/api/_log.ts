const SECRET_HINTS = /(key|secret|token|password|authorization|signature)/i

/**
 * Structured server logs. We record the identifiers needed to trace a call
 * (organization, provider request id, call id, campaign id, event, outcome)
 * and strip anything that looks like a credential. Customer content such as
 * transcripts is never logged.
 */
function redact(value: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {}
  for (const [key, item] of Object.entries(value)) {
    if (SECRET_HINTS.test(key)) continue
    if (item && typeof item === "object" && !Array.isArray(item)) {
      out[key] = redact(item as Record<string, unknown>)
      continue
    }
    out[key] = item
  }
  return out
}

export function log(event: string, fields: Record<string, unknown> = {}): void {
  console.log(
    JSON.stringify({
      event,
      ts: new Date().toISOString(),
      ...redact(fields),
    })
  )
}

export function logError(event: string, error: unknown, fields: Record<string, unknown> = {}): void {
  const message = error instanceof Error ? error.message : String(error)
  console.error(JSON.stringify({ event, level: "error", message, ts: new Date().toISOString(), ...redact(fields) }))
}
