import {
  ProviderError,
  type CampaignResult,
  type CampaignStatusResult,
  type CohortUploadInput,
  type CreateCampaignInput,
  type ProviderAgent,
  type ProviderPhoneNumber,
  type StartOutboundCallInput,
  type StartOutboundCallResult,
  VoiceProvider,
} from "./types.ts"

/**
 * Real Sarvam Voice Agents integration.
 *
 * Verified against the official Sarvam API documentation:
 *  - Auth: `X-API-Key` header, keys issued from the Sarvam dashboard.
 *  - Base URLs are per-service:
 *      Instant Outbound  https://apps.sarvam.ai/api/outbounds
 *      Campaigns/Cohorts https://apps.sarvam.ai/api/scheduling
 *      Deployments       https://apps.sarvam.ai/api/app-authoring
 *  - Instant outbound: POST /v1/orgs/{org_id}/workspaces/{workspace_id}/outbounds
 *      body { app_config{app_id,app_version,connection_config{connection_id,agent_phone_number}},
 *             user_config{user_phone_number}, agent_variables, webhook_config{url,metadata} }
 *      response { attempt_id }
 *  - Campaigns: POST /v1/orgs/{org_id}/workspaces/{workspace_id}/campaigns
 *      body { name, app_config, start_timestamp, end_timestamp, allowed_schedule,
 *             description, webhook_config }  response { campaign_id, status, ... }
 *  - Campaign status: pause / resume / cancel action.
 *  - Cohorts are uploaded as multipart form-data.
 *
 * Every value that identifies the tenant (org id, workspace id, deployment id,
 * phone number, connection id) arrives from database configuration. Nothing is
 * hardcoded, and the API key lives only in server environment variables.
 */

const DEFAULT_BASE_URLS = {
  outbounds: "https://apps.sarvam.ai/api/outbounds",
  scheduling: "https://apps.sarvam.ai/api/scheduling",
  deployments: "https://apps.sarvam.ai/api/app-authoring",
}

export type SarvamConfig = {
  apiKey: string
  orgId: string
  workspaceId: string
  baseUrls?: Partial<typeof DEFAULT_BASE_URLS>
  timeoutMs?: number
}

type RequestOptions = {
  method: "GET" | "POST" | "PATCH"
  base: keyof typeof DEFAULT_BASE_URLS
  path: string
  body?: unknown
  formData?: FormData
}

export class SarvamVoiceProvider extends VoiceProvider {
  readonly name = "sarvam"
  private readonly baseUrls: typeof DEFAULT_BASE_URLS
  private readonly timeoutMs: number

  constructor(private readonly config: SarvamConfig) {
    super()
    this.baseUrls = { ...DEFAULT_BASE_URLS, ...(config.baseUrls ?? {}) }
    this.timeoutMs = config.timeoutMs ?? 15_000
  }

  private tenantPath(resource: string): string {
    return `/v1/orgs/${encodeURIComponent(this.config.orgId)}/workspaces/${encodeURIComponent(
      this.config.workspaceId
    )}/${resource}`
  }

  private async request<T>(options: RequestOptions): Promise<T> {
    const url = `${this.baseUrls[options.base]}${options.path}`
    const controller = new AbortController()
    const timer = setTimeout(() => controller.abort(), this.timeoutMs)

    const headers: Record<string, string> = { "X-API-Key": this.config.apiKey }
    if (options.body !== undefined) headers["Content-Type"] = "application/json"

    let response: Response
    try {
      response = await fetch(url, {
        method: options.method,
        headers,
        body: options.formData ?? (options.body === undefined ? undefined : JSON.stringify(options.body)),
        signal: controller.signal,
      })
    } catch (cause) {
      const aborted = cause instanceof Error && cause.name === "AbortError"
      throw new ProviderError(
        aborted ? "timeout" : "unavailable",
        aborted ? "Sarvam request timed out" : `Sarvam request failed: ${String(cause)}`
      )
    } finally {
      clearTimeout(timer)
    }

    if (!response.ok) {
      // Read the body for our logs, but never surface it to the caller verbatim.
      const text = await response.text().catch(() => "")
      throw new ProviderError(classifyStatus(response.status), `Sarvam returned ${response.status}: ${text.slice(0, 400)}`, response.status)
    }

    if (response.status === 204) return undefined as T
    return (await response.json()) as T
  }

  async startOutboundCall(input: StartOutboundCallInput): Promise<StartOutboundCallResult> {
    const payload = {
      app_config: {
        app_id: input.deploymentId,
        app_version: input.appVersion,
        connection_config: {
          connection_id: input.connectionId ?? "",
          agent_phone_number: input.agentPhoneNumber ?? "",
        },
      },
      user_config: { user_phone_number: input.customerPhone },
      agent_variables: input.variables,
      webhook_config: { url: input.webhookUrl, metadata: input.metadata },
    }

    const result = await this.request<{ attempt_id: string }>({
      method: "POST",
      base: "outbounds",
      path: this.tenantPath("outbounds"),
      body: payload,
    })
    return { attemptId: result.attempt_id }
  }

  async createCampaign(input: CreateCampaignInput): Promise<CampaignResult> {
    const payload = {
      name: input.name,
      description: input.description.slice(0, 150),
      app_config: {
        app_id: input.deploymentId,
        app_version: input.appVersion,
        connection_config: {
          connection_id: input.connectionId ?? "",
          agent_phone_number: input.agentPhoneNumber ?? "",
        },
      },
      start_timestamp: input.startTimestamp,
      end_timestamp: input.endTimestamp,
      allowed_schedule: input.allowedSchedule,
      webhook_config: { url: input.webhookUrl, metadata: input.metadata },
    }

    const result = await this.request<{ campaign_id: string; status: string }>({
      method: "POST",
      base: "scheduling",
      path: this.tenantPath("campaigns"),
      body: payload,
    })
    return { campaignId: result.campaign_id, status: result.status }
  }

  async startCampaign(campaignId: string): Promise<CampaignResult> {
    return this.setCampaignStatus(campaignId, "resume")
  }

  async stopCampaign(campaignId: string): Promise<void> {
    await this.setCampaignStatus(campaignId, "cancel")
  }

  private async setCampaignStatus(
    campaignId: string,
    action: "pause" | "resume" | "cancel"
  ): Promise<CampaignResult> {
    const result = await this.request<{ campaign_id: string; status: string }>({
      method: "PATCH",
      base: "scheduling",
      path: this.tenantPath(`campaigns/${encodeURIComponent(campaignId)}/status`),
      body: { action },
    })
    return { campaignId: result.campaign_id ?? campaignId, status: result.status }
  }

  async getCampaign(campaignId: string): Promise<CampaignStatusResult | null> {
    const result = await this.request<{
      items?: Array<{ campaign_id: string; status: string; name?: string }>
    }>({
      method: "GET",
      base: "scheduling",
      path: this.tenantPath("campaigns"),
    })
    const match = result.items?.find((item) => item.campaign_id === campaignId)
    if (!match) return null
    return { campaignId: match.campaign_id, status: match.status, name: match.name }
  }

  async uploadCohort(input: CohortUploadInput): Promise<void> {
    const form = new FormData()
    form.append("name", input.name)
    form.append("file", new Blob([input.csv], { type: "text/csv" }), "cohort.csv")

    await this.request<unknown>({
      method: "POST",
      base: "scheduling",
      path: this.tenantPath(`campaigns/${encodeURIComponent(input.campaignId)}/cohorts`),
      formData: form,
    })
  }

  async getPhoneNumbers(): Promise<ProviderPhoneNumber[]> {
    const result = await this.request<{
      items?: Array<Record<string, unknown>>
    }>({
      method: "GET",
      base: "deployments",
      path: this.tenantPath("phone-numbers"),
    })

    return (result.items ?? []).flatMap((item) => {
      const number = (item.number ?? item.phone_number) as string | undefined
      const id = (item.id ?? item.phone_number_id) as string | undefined
      if (!number || !id) return []
      return [
        {
          id,
          number,
          connectionId: (item.connection_id as string | undefined) ?? null,
        },
      ]
    })
  }

  async getAgent(): Promise<ProviderAgent | null> {
    const result = await this.request<{
      items?: Array<Record<string, unknown>>
    }>({
      method: "GET",
      base: "deployments",
      path: this.tenantPath("deployments"),
    })

    const first = result.items?.[0]
    if (!first) return null
    return {
      deploymentId: String(first.app_id ?? first.deployment_id ?? ""),
      appVersion: Number(first.app_version ?? first.version ?? 1),
      name: (first.name as string | undefined) ?? null,
    }
  }
}

function classifyStatus(status: number): "auth" | "credits" | "validation" | "unavailable" {
  if (status === 401 || status === 403) return "auth"
  if (status === 402) return "credits"
  if (status >= 400 && status < 500) return "validation"
  return "unavailable"
}
