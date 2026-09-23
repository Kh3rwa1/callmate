import type { Call, CallOutcome } from "@/data/models/call"
import type { Campaign, CampaignDraft } from "@/data/models/campaign"
import type { Contact } from "@/data/models/contact"

/**
 * The app's view of the backend.
 *
 * Every method is implemented by `backendRepositories`, which calls our own API.
 * The API is the only component that holds the voice provider credentials and
 * the only writer of business state, so these interfaces deliberately expose no
 * way to "complete a call locally".
 */
export interface VoiceAgentRepository {
  /** POST /api/calls/outbound */
  startOutboundCall(contactId: string): Promise<{ callId: string }>
  /** GET /api/ai-agent */
  getInboundAgentConfig(): Promise<{ greeting: string; enabled: boolean }>
  /** PATCH /api/ai-agent */
  configureInboundAgent(config: { greeting: string; enabled: boolean }): Promise<void>
  /** GET /api/bootstrap (usage section) */
  getUsage(): Promise<{ minutesUsed: number; callsMade: number }>
}

export interface CallRepository {
  /** GET /api/calls */
  listCalls(): Promise<Call[]>
  /** GET /api/calls/:id */
  getCall(callId: string): Promise<Call | null>
  /** GET /api/calls/:id/transcript — the only place a transcript is loaded */
  getCallTranscript(callId: string): Promise<Array<{ speaker: "ai" | "customer"; text: string }>>
  /** POST /api/calls/:id/complete */
  completeCall(callId: string, outcome: CallOutcome): Promise<Call>
}

export interface CampaignRepository {
  /** POST /api/campaigns */
  startCampaign(draft: CampaignDraft): Promise<Campaign>
  /** GET /api/campaigns/:id */
  getCampaignStatus(campaignId: string): Promise<Campaign | null>
  /** POST /api/campaigns/:id/step — advances a round in mock mode */
  advanceCampaign(campaignId: string): Promise<Campaign | null>
  /** POST /api/campaigns/:id/stop */
  stopCampaign(campaignId: string): Promise<void>
}

export interface ContactRepository {
  /** GET /api/bootstrap (contacts section) */
  listContacts(): Promise<Contact[]>
  /** POST /api/contacts */
  createContact(input: { name: string; phone: string; service: string }): Promise<Contact>
  /** PATCH /api/contacts/:id */
  updateContact(
    contactId: string,
    patch: { name?: string; phone?: string; service?: string; notes?: string }
  ): Promise<void>
}

export interface FollowUpRepository {
  /** PATCH /api/follow-ups/:id */
  markDone(followUpId: string): Promise<void>
}

export type RepositoryBundle = {
  voiceAgent: VoiceAgentRepository
  calls: CallRepository
  campaigns: CampaignRepository
  contacts: ContactRepository
  followUps: FollowUpRepository
}
