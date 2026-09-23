import { SarvamVoiceProvider, type SarvamConfig } from "./sarvam.ts"
import { VoiceProvider } from "./types.ts"

export { ProviderError } from "./types.ts"
export type { VoiceProvider } from "./types.ts"

export type OrgVoiceConfig = {
  sarvamOrgId: string | null
  sarvamWorkspaceId: string | null
  sarvamDeploymentId: string | null
  sarvamAppVersion: number
  voiceMode: string
}

/**
 * Chooses the provider for a request.
 *
 * MOCK mode returns `null`, and the caller simulates the provider: the app stays
 * fully usable before any Sarvam credentials exist. SARVAM mode requires the
 * tenant's own org/workspace/deployment ids plus the server-side API key; if any
 * is missing we raise a configuration error the user can act on, rather than
 * silently pretending to call.
 */
export function resolveVoiceProvider(
  org: OrgVoiceConfig,
  env: { apiKey?: string; baseUrl?: string }
): VoiceProvider | null {
  if (org.voiceMode !== "sarvam") return null

  const apiKey = env.apiKey?.trim()
  const orgId = org.sarvamOrgId?.trim()
  const workspaceId = org.sarvamWorkspaceId?.trim()

  if (!apiKey || !orgId || !workspaceId || !org.sarvamDeploymentId?.trim()) {
    throw new Error("sarvam_not_configured")
  }

  const config: SarvamConfig = { apiKey, orgId, workspaceId }
  return new SarvamVoiceProvider(config)
}
