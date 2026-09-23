/**
 * The provider-neutral surface our backend depends on. Everything above this
 * layer (API routes, database writes, the Flutter/web app) is written against
 * these types, so swapping Sarvam for another voice platform later is a new
 * `VoiceProvider` subclass and nothing else.
 */

export type StartOutboundCallInput = {
  /** The deployed agent to run the call against. */
  deploymentId: string
  appVersion: number
  customerPhone: string
  customerName: string
  /** Structured fields the agent fills in during the call and returns in the webhook. */
  variables: Record<string, unknown>
  /** The business number the call is placed from. */
  agentPhoneNumber: string | null
  /** Telephony connection the number belongs to. */
  connectionId: string | null
  webhookUrl: string
  metadata: Record<string, unknown>
}

export type StartOutboundCallResult = {
  attemptId: string
}

export type CampaignSchedule = Record<string, unknown>

export type CreateCampaignInput = {
  name: string
  description: string
  deploymentId: string
  appVersion: number
  agentPhoneNumber: string | null
  connectionId: string | null
  startTimestamp: string
  endTimestamp: string
  allowedSchedule: CampaignSchedule
  webhookUrl: string
  metadata: Record<string, unknown>
}

export type CampaignResult = {
  campaignId: string
  status: string
}

export type CampaignStatusResult = {
  campaignId: string
  status: string
  name?: string
}

export type CohortUploadInput = {
  campaignId: string
  name: string
  /** CSV body: one row per customer. */
  csv: string
}

export type ProviderPhoneNumber = {
  id: string
  number: string
  connectionId: string | null
}

export type ProviderAgent = {
  deploymentId: string
  appVersion: number
  name: string | null
}

/** Raised when the provider rejects a request for a reason the caller can fix. */
export class ProviderError extends Error {
  constructor(
    readonly kind:
      | "auth"
      | "credits"
      | "validation"
      | "unavailable"
      | "timeout"
      | "unknown",
    message: string,
    readonly status?: number
  ) {
    super(message)
    this.name = "ProviderError"
  }
}

export abstract class VoiceProvider {
  abstract readonly name: string
  abstract startOutboundCall(input: StartOutboundCallInput): Promise<StartOutboundCallResult>
  abstract createCampaign(input: CreateCampaignInput): Promise<CampaignResult>
  abstract startCampaign(campaignId: string): Promise<CampaignResult>
  abstract getCampaign(campaignId: string): Promise<CampaignStatusResult | null>
  abstract stopCampaign(campaignId: string): Promise<void>
  abstract uploadCohort(input: CohortUploadInput): Promise<void>
  abstract getPhoneNumbers(): Promise<ProviderPhoneNumber[]>
  abstract getAgent(): Promise<ProviderAgent | null>
}
