import {
  AI_CALL_STYLES,
  AI_LANGUAGES,
  AI_VOICES,
  type AiEmployee,
  type Business,
} from "@/data/models/business"
import {
  NOTIFICATION_LABELS,
  type NotificationChannel,
  type NotificationSettings,
  type Subscription,
  type Usage,
} from "@/data/models/account"
import type { Contact, ContactStatus } from "@/data/models/contact"
import type { Call, CallFilter } from "@/data/models/call"
import type { Campaign } from "@/data/models/campaign"
import type { FollowUp } from "@/data/models/followUp"
import { BRAND } from "@/core/constants/brand"
import {
  computeDashboardStats,
  countByStatus,
  pendingFollowUps,
  type DashboardStats,
  type PipelineCounts,
} from "@/data/services/stats"

export type AppData = {
  contacts: Contact[]
  calls: Call[]
  followUps: FollowUp[]
  campaigns: Campaign[]
}

export type LoadStatus = "idle" | "loading" | "ready" | "error"

export type AppState = {
  hydrated: boolean
  business: Business
  onboardingComplete: boolean
  aiEmployee: AiEmployee
  session: { userId: string; email: string; name: string } | null
  data: AppData
  selectedStage: ContactStatus
  callFilter: CallFilter
  loadStatus: LoadStatus
  loadError: string | null
  notifications: NotificationSettings
  subscription: Subscription
  usage: Usage
  lastCompletedCallId: string | null
  toast: string | null
}

/**
 * Note on what is NOT here any more: call, campaign and follow-up outcomes are
 * no longer mutated in the browser. The backend owns those writes (it is the
 * only thing that can talk to the voice provider), and the store is refreshed
 * from it via `refresh`. Local state is limited to presentation concerns —
 * navigation, filters, preferences and text the user is still editing.
 */
export type Action =
  | { type: "hydrate"; payload: Partial<AppState> }
  | { type: "refresh"; data: AppData; usage?: Partial<Usage> }
  | { type: "setLoadStatus"; status: LoadStatus; error?: string | null }
  | { type: "setBusiness"; business: Business; onboardingComplete: boolean }
  | { type: "setSession"; session: AppState["session"] }
  | { type: "setSelectedStage"; stage: ContactStatus }
  | { type: "setCallFilter"; filter: CallFilter }
  | { type: "updateContact"; contactId: string; patch: Partial<Contact> }
  | { type: "completeFollowUp"; followUpId: string }
  | { type: "updateAiEmployee"; patch: Partial<AiEmployee> }
  | { type: "updateAiSettings"; patch: Partial<AiEmployee["settings"]> }
  | { type: "toggleNotification"; channel: NotificationChannel }
  | { type: "setToast"; message: string | null }

export function createInitialState(seed: AppData, business: Business): AppState {
  return {
    hydrated: false,
    business,
    onboardingComplete: false,
    aiEmployee: {
      name: BRAND.employeeName,
      active: true,
      answeringMode: "both",
      settings: {
        voice: AI_VOICES[0],
        language: AI_LANGUAGES[2],
        callStyle: AI_CALL_STYLES[0],
        workingHoursStart: "09:00",
        workingHoursEnd: "19:00",
        followUpAutomation: true,
        autoWhatsApp: true,
      },
    },
    session: null,
    data: seed,
    selectedStage: "new",
    callFilter: "all",
    loadStatus: "idle",
    loadError: null,
    notifications: {
      calls: true,
      bookings: true,
      followUps: true,
      payments: true,
    },
    subscription: {
      plan: "growth",
      planLabel: "Growth",
      pricePerMonth: 2999,
      minutesIncluded: 3000,
      renewsOn: new Date(Date.now() + 12 * 86_400_000).toISOString().slice(0, 10),
      active: true,
    },
    usage: {
      minutesUsed: 0,
      callsMade: 0,
      whatsappSent: 0,
      cycleStart: new Date().toISOString().slice(0, 10),
    },
    lastCompletedCallId: null,
    toast: null,
  }
}

function patchContact(
  contacts: Contact[],
  contactId: string,
  patch: Partial<Contact>
): Contact[] {
  return contacts.map((contact) =>
    contact.id === contactId ? { ...contact, ...patch } : contact
  )
}

export function reducer(state: AppState, action: Action): AppState {
  switch (action.type) {
    case "hydrate":
      return { ...state, ...action.payload, hydrated: true }

    case "refresh":
      // The backend has already applied the business change; we simply adopt its
      // version of the data so the screens can never disagree with it.
      return {
        ...state,
        data: action.data,
        usage: action.usage ? { ...state.usage, ...action.usage } : state.usage,
      }

    case "setLoadStatus":
      return { ...state, loadStatus: action.status, loadError: action.error ?? null }

    case "setBusiness":
      return {
        ...state,
        business: action.business,
        onboardingComplete: action.onboardingComplete,
      }

    case "setSession":
      return { ...state, session: action.session }

    case "setSelectedStage":
      return { ...state, selectedStage: action.stage }

    case "setCallFilter":
      return { ...state, callFilter: action.filter }

    case "updateContact":
      return {
        ...state,
        data: {
          ...state.data,
          contacts: patchContact(state.data.contacts, action.contactId, action.patch),
        },
      }

    case "completeFollowUp":
      return {
        ...state,
        data: {
          ...state.data,
          followUps: state.data.followUps.map((item) =>
            item.id === action.followUpId ? { ...item, status: "done" as const } : item
          ),
        },
        toast: "Follow-up marked as done",
      }

    case "updateAiEmployee":
      return { ...state, aiEmployee: { ...state.aiEmployee, ...action.patch } }

    case "updateAiSettings":
      return {
        ...state,
        aiEmployee: {
          ...state.aiEmployee,
          settings: { ...state.aiEmployee.settings, ...action.patch },
        },
      }

    case "toggleNotification":
      return {
        ...state,
        notifications: {
          ...state.notifications,
          [action.channel]: !state.notifications[action.channel],
        },
      }

    case "setToast":
      return { ...state, toast: action.message }

    default:
      return state
  }
}

export type Selectors = {
  dashboardStats: DashboardStats
  pipelineCounts: PipelineCounts
  pendingFollowUpsList: FollowUp[]
  activeCalls: Call[]
}

/** All dashboard numbers are derived, never stored, so they cannot go stale. */
export function selectDerived(state: AppState): Selectors {
  return {
    dashboardStats: computeDashboardStats(
      state.data.contacts,
      state.data.calls,
      state.data.followUps
    ),
    pipelineCounts: countByStatus(state.data.contacts),
    pendingFollowUpsList: pendingFollowUps(state.data.followUps),
    activeCalls: state.data.calls.filter(
      (call) => call.status === "calling" || call.status === "connected"
    ),
  }
}

export { NOTIFICATION_LABELS }
