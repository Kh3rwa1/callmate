import { backend } from "@/data/backend/client"
import { mapCall, mapCampaign, mapContact, mapFollowUp } from "@/data/backend/mappers"
import type { BootstrapPayload } from "@/data/backend/types"
import type {
  CallRepository,
  CampaignRepository,
  ContactRepository,
  FollowUpRepository,
  VoiceAgentRepository,
} from "@/data/repositories/types"
import type { AppData } from "@/core/state/appReducer"
import type { CallOutcome } from "@/data/models/call"
import type { CampaignDraft } from "@/data/models/campaign"

/**
 * Turns a bootstrap payload into the view models the screens render. Kept in one
 * place so a refresh always produces a consistent snapshot: contacts with their
 * timelines, calls, follow-ups and campaigns with their membership.
 */
export function toAppData(payload: BootstrapPayload): AppData {
  return {
    contacts: payload.contacts.map((row) => mapContact(row, payload.timeline[row.id] ?? [])),
    calls: payload.calls.map(mapCall),
    followUps: payload.followUps.map(mapFollowUp),
    campaigns: payload.campaigns.map((row) => mapCampaign(row, payload.campaignContacts[row.id] ?? [])),
  }
}

export function createBackendRepositories(refresh: () => Promise<void>): {
  bundle: {
    voiceAgent: VoiceAgentRepository
    calls: CallRepository
    campaigns: CampaignRepository
    contacts: ContactRepository
    followUps: FollowUpRepository
  }
  toAppData: typeof toAppData
} {
  const bundle = {
    voiceAgent: createVoiceAgentRepository(refresh),
    calls: createCallRepository(refresh),
    campaigns: createCampaignRepository(refresh),
    contacts: createContactRepository(refresh),
    followUps: createFollowUpRepository(refresh),
  }
  return { bundle, toAppData }
}

function createVoiceAgentRepository(refresh: () => Promise<void>): VoiceAgentRepository {
  return {
    async startOutboundCall(contactId: string) {
      const result = await backend.startOutboundCall({ contactId })
      return { callId: result.callId }
    },

    async getInboundAgentConfig() {
      const payload = await backend.aiAgent()
      return {
        greeting: payload.agent?.greeting ?? "",
        enabled: payload.agent?.inbound_enabled ?? true,
      }
    },

    async configureInboundAgent(config) {
      await backend.updateAgent({ greeting: config.greeting, inbound_enabled: config.enabled })
      await refresh()
    },

    async getUsage() {
      const payload = await backend.bootstrap()
      return {
        minutesUsed: Number(payload.usage?.minutes_used ?? 0),
        callsMade: payload.usage?.calls_made ?? 0,
      }
    },
  }
}

function createCallRepository(refresh: () => Promise<void>): CallRepository {
  return {
    async listCalls() {
      const payload = await backend.bootstrap()
      return payload.calls.map(mapCall)
    },

    async getCall(callId: string) {
      const payload = await backend.bootstrap()
      const row = payload.calls.find((call) => call.id === callId)
      return row ? mapCall(row) : null
    },

    /** Transcripts are fetched only here, never bundled with the call list. */
    async getCallTranscript(callId: string) {
      const payload = await backend.transcript(callId)
      return payload.turns.map((turn) => ({
        speaker: turn.speaker === "customer" ? ("customer" as const) : ("ai" as const),
        text: turn.text,
      }))
    },

    async completeCall(callId: string, outcome: CallOutcome) {
      await backend.completeCall({ callId, outcome })
      // The backend has already moved the customer and the campaign counters;
      // re-read its state rather than guessing at it here.
      await refresh()
      const payload = await backend.bootstrap()
      const row = payload.calls.find((call) => call.id === callId)
      return row ? mapCall(row) : ({} as never)
    },
  }
}

function createCampaignRepository(refresh: () => Promise<void>): CampaignRepository {
  return {
    async startCampaign(draft: CampaignDraft) {
      const created = await backend.createCampaign({
        contactIds: draft.contactIds,
        purpose: draft.purpose,
        scheduledFor: draft.timing === "scheduled" ? draft.scheduledFor ?? null : null,
      })
      await refresh()
      const campaign = await this.getCampaignStatus(created.campaignId)
      return (
        campaign ?? {
          id: created.campaignId,
          name: "Calling round",
          purpose: draft.purpose,
          contactIds: draft.contactIds,
          startedAt: new Date().toISOString(),
          endedAt: null,
          status: draft.timing === "scheduled" ? "draft" : "running",
          total: draft.contactIds.length,
          completed: 0,
          booked: 0,
          interested: 0,
          followUps: 0,
          noAnswer: 0,
        }
      )
    },

    async getCampaignStatus(campaignId: string) {
      const payload = await backend.bootstrap()
      const row = payload.campaigns.find((campaign) => campaign.id === campaignId)
      return row ? mapCampaign(row, payload.campaignContacts[campaignId] ?? []) : null
    },

    /**
     * Advances the round one call. In MOCK mode the backend simulates the call
     * and its outcome; in SARVAM mode the provider calls customers itself, so
     * this simply reports the round's current state.
     */
    async advanceCampaign(campaignId: string) {
      await backend.advanceCampaign(campaignId)
      await refresh()
      return this.getCampaignStatus(campaignId)
    },

    async stopCampaign(campaignId: string) {
      await backend.stopCampaign(campaignId)
      await refresh()
    },
  }
}

function createContactRepository(refresh: () => Promise<void>): ContactRepository {
  return {
    async listContacts() {
      const payload = await backend.bootstrap()
      return payload.contacts.map((row) => mapContact(row, payload.timeline[row.id] ?? []))
    },

    async createContact(input) {
      const created = await backend.createContact(input)
      await refresh()
      return mapContact(created.contact)
    },

    async updateContact(contactId, patch) {
      await backend.updateContact(contactId, patch)
      await refresh()
    },
  }
}

function createFollowUpRepository(refresh: () => Promise<void>): FollowUpRepository {
  return {
    async markDone(followUpId: string) {
      await backend.markFollowUpDone(followUpId)
      await refresh()
    },
  }
}
