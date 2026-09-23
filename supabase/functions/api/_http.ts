export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Client-Info, Apikey",
}

/**
 * An error we are willing to show the user. `userMessage` is always plain
 * language; `detail` is for our logs only and never leaves the server.
 */
export class ApiError extends Error {
  constructor(
    readonly code: string,
    readonly status: number,
    readonly userMessage: string,
    readonly detail?: string
  ) {
    super(detail ?? userMessage)
    this.name = "ApiError"
  }
}

export const noAnswer = () =>
  new ApiError("invalid_phone", 400, "That phone number doesn't look right. Please check and try again.")

export const providerUnavailable = (detail: string) =>
  new ApiError(
    "provider_unavailable",
    503,
    "The calling service is busy right now. Please try again in a moment.",
    detail
  )

export const notConfigured = (what: string) =>
  new ApiError(
    "not_configured",
    409,
    "Calling isn't connected yet. Add your voice service details in Settings and try again.",
    what
  )

export const outOfCredits = (detail?: string) =>
  new ApiError(
    "insufficient_credits",
    402,
    "You've run out of calling credits this month. Renew your plan to keep calling.",
    detail
  )

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  })
}

export function preflight(): Response {
  return new Response(null, { status: 200, headers: corsHeaders })
}

export function errorResponse(error: unknown): Response {
  if (error instanceof ApiError) {
    return json({ error: { code: error.code, message: error.userMessage } }, error.status)
  }
  return json(
    { error: { code: "server_error", message: "Something went wrong on our side. Please try again." } },
    500
  )
}
