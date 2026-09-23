/**
 * Centralised route table. Every navigation in the app goes through `ROUTES` so
 * a path is never written as a string literal inside a screen.
 */
export const ROUTES = {
  welcome: "/welcome",
  login: "/login",
  onboardingBusiness: "/onboarding/business",

  home: "/home",
  pipeline: "/pipeline",
  customer: (id: string) => `/customer/${id}`,
  calls: "/calls",
  liveCall: (id: string) => `/calls/live/${id}`,
  callResult: (id: string) => `/calls/result/${id}`,
  startCalling: "/calls/start",
  campaign: (id: string) => `/calls/campaign/${id}`,
  followUps: "/followups",
  whatsapp: (contactId: string) => `/whatsapp/${contactId}`,
  more: "/more",

  aiEmployee: "/ai-employee",
  business: "/business",
  phoneNumber: "/phone-number",
  notifications: "/notifications",
  subscription: "/subscription",
  usage: "/usage",
} as const

export type RouteId =
  | "welcome"
  | "login"
  | "onboardingBusiness"
  | "home"
  | "pipeline"
  | "customer"
  | "calls"
  | "liveCall"
  | "callResult"
  | "startCalling"
  | "campaign"
  | "followUps"
  | "whatsapp"
  | "more"
  | "aiEmployee"
  | "business"
  | "phoneNumber"
  | "notifications"
  | "subscription"
  | "usage"

/** The five primary destinations that own the bottom navigation bar. */
export const PRIMARY_TABS: Array<{ id: RouteId; path: string; label: string }> = [
  { id: "home", path: ROUTES.home, label: "Home" },
  { id: "pipeline", path: ROUTES.pipeline, label: "Pipeline" },
  { id: "calls", path: ROUTES.calls, label: "Calls" },
  { id: "followUps", path: ROUTES.followUps, label: "Follow-ups" },
  { id: "more", path: ROUTES.more, label: "More" },
]

export function isPrimaryPath(pathname: string) {
  return PRIMARY_TABS.some((tab) => tab.path === pathname)
}

type RoutePattern = {
  pattern: string
  segments: string[]
}

const PATTERNS: Array<{ id: RouteId; build: (...args: string[]) => string }> = [
  { id: "home", build: () => ROUTES.home },
  { id: "pipeline", build: () => ROUTES.pipeline },
  { id: "customer", build: (id) => ROUTES.customer(id) },
  { id: "liveCall", build: (id) => ROUTES.liveCall(id) },
  { id: "callResult", build: (id) => ROUTES.callResult(id) },
  { id: "startCalling", build: () => ROUTES.startCalling },
  { id: "campaign", build: (id) => ROUTES.campaign(id) },
  { id: "calls", build: () => ROUTES.calls },
  { id: "followUps", build: () => ROUTES.followUps },
  { id: "whatsapp", build: (id) => ROUTES.whatsapp(id) },
  { id: "more", build: () => ROUTES.more },
  { id: "aiEmployee", build: () => ROUTES.aiEmployee },
  { id: "business", build: () => ROUTES.business },
  { id: "phoneNumber", build: () => ROUTES.phoneNumber },
  { id: "notifications", build: () => ROUTES.notifications },
  { id: "subscription", build: () => ROUTES.subscription },
  { id: "usage", build: () => ROUTES.usage },
  { id: "welcome", build: () => ROUTES.welcome },
  { id: "login", build: () => ROUTES.login },
  { id: "onboardingBusiness", build: () => ROUTES.onboardingBusiness },
]

const COMPILED: RoutePattern[] = PATTERNS.map(({ id, build }) => {
  // The placeholder name must be `id` because screens read `match.params.id`.
  const sample = build(":id")
  return { pattern: id, segments: sample.split("/").filter(Boolean) }
})

/** Returns the route id plus any captured params such as `:id`. */
export function matchRoute(pathname: string) {
  const parts = pathname.split("/").filter(Boolean)
  for (const compiled of COMPILED) {
    if (compiled.segments.length !== parts.length) continue
    const params: Record<string, string> = {}
    const matched = compiled.segments.every((segment, index) => {
      if (segment.startsWith(":")) {
        params[segment.slice(1)] = decodeURIComponent(parts[index])
        return true
      }
      return segment === parts[index]
    })
    if (matched) return { id: compiled.pattern as RouteId, params }
  }
  return null
}
