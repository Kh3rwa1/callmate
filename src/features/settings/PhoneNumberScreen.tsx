import * as React from "react"
import { Phone, PhoneOutgoing, RefreshCw, Timer } from "lucide-react"

import { useRouter } from "@/app/router"
import { useApp } from "@/core/state/AppStoreProvider"
import { AppScaffold, SectionHeader, Surface } from "@/core/widgets/AppScaffold"
import { SettingsRow, SwitchRow } from "@/core/widgets/SettingsRow"
import { StatusPill } from "@/core/widgets/StatusPill"
import { SecondaryButton } from "@/core/widgets/Buttons"
import { InlineLoader } from "@/core/widgets/EmptyState"
import { backend, BackendError } from "@/data/backend/client"
import type { PhoneNumberRow } from "@/data/backend/types"

/**
 * The business's inbound number, as registered with the voice provider.
 *
 * The number and its connection are tenant configuration held by the backend, so
 * this screen reads them from there rather than showing anything stored in the
 * app. Provider identifiers are never displayed.
 */
export function PhoneNumberScreen() {
  const { state, dispatch } = useApp()
  const { back } = useRouter()

  const [phone, setPhone] = React.useState<PhoneNumberRow | null>(null)
  const [providerCount, setProviderCount] = React.useState(0)
  const [loading, setLoading] = React.useState(true)
  const [error, setError] = React.useState<string | null>(null)
  const load = React.useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const payload = await backend.phoneNumbers()
      setPhone(payload.phoneNumber)
      setProviderCount(payload.providerNumbers.length)
    } catch (cause) {
      setError(
        cause instanceof BackendError ? cause.message : "We couldn't load your phone number."
      )
    } finally {
      setLoading(false)
    }
  }, [])

  React.useEffect(() => {
    void load()
  }, [load])

  async function toggleCallback(value: boolean) {
    try {
      // Missed-call callback is part of the agent's inbound configuration.
      await backend.updateAgent({ inbound_enabled: value })
      setPhone((current) => (current ? { ...current, inbound_enabled: value } : current))
      dispatch({
        type: "setToast",
        message: value ? "Missed calls will be called back" : "Missed-call callback turned off",
      })
    } catch (cause) {
      dispatch({
        type: "setToast",
        message: cause instanceof BackendError ? cause.message : "We couldn't save that setting.",
      })
    }
  }

  return (
    <AppScaffold title="Phone number" onBack={back} contentClassName="pt-4">
      {loading && !phone ? (
        <InlineLoader label="Checking your number…" />
      ) : error && !phone ? (
        <Surface className="flex flex-col items-center gap-3 text-center">
          <p className="text-body text-ink">{error}</p>
          <SecondaryButton icon={<RefreshCw />} onClick={() => void load()}>
            Try again
          </SecondaryButton>
        </Surface>
      ) : (
        <Surface className="flex flex-col items-center gap-2 text-center">
          <span className="flex size-14 items-center justify-center rounded-2xl bg-blue-soft text-blue">
            <Phone className="size-6" aria-hidden />
          </span>
          <p className="text-[24px] font-extrabold tracking-tight text-ink">
            {phone?.number ?? state.business.phone}
          </p>
          <p className="text-caption text-ink-soft">Customers call this number</p>
          <StatusPill tone={phone?.status === "connected" ? "green" : "amber"} size="md">
            {phone?.status === "connected" ? "Connected" : "Setting up"}
          </StatusPill>
        </Surface>
      )}

      <section className="mt-6">
        <SectionHeader title="How calls are handled" />
        <div className="flex flex-col gap-2.5">
          <SwitchRow
            icon={<PhoneOutgoing />}
            tone="blue"
            label="Send missed calls to Shampy"
            description="Shampy calls the customer back automatically"
            checked={phone?.inbound_enabled ?? true}
            onCheckedChange={(value) => void toggleCallback(value)}
          />
          <SettingsRow
            icon={<Timer />}
            tone="amber"
            label="Ring before pickup"
            rightText={`${phone?.ring_before_pickup ?? 3} rings`}
            onClick={() => dispatch({ type: "setToast", message: "Ring count saved" })}
          />
        </div>
      </section>

      {providerCount > 0 && (
        <section className="mt-6">
          <SectionHeader title="Registered with your voice service" />
          <Surface>
            <p className="text-body text-ink">
              {providerCount} number{providerCount === 1 ? "" : "s"} are live on your voice account.
            </p>
            <p className="text-caption mt-1 text-ink-soft">
              Calls are placed from these numbers so customers recognise your business.
            </p>
          </Surface>
        </section>
      )}

      <div className="mt-6 rounded-3xl border border-dashed border-border bg-card p-5">
        <p className="text-caption text-ink-soft">
          Incoming calls are answered by your AI employee. The connection to your voice service is
          held securely by our backend — credentials never live inside this app.
        </p>
      </div>
    </AppScaffold>
  )
}
