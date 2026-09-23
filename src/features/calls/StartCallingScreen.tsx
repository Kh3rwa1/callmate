import * as React from "react"
import { CalendarClock, PhoneCall, Zap } from "lucide-react"

import { BRAND } from "@/core/constants/brand"
import { ROUTES } from "@/app/routes"
import { useRouter } from "@/app/router"
import { useApp } from "@/core/state/AppStoreProvider"
import { AppScaffold, SectionHeader, Surface } from "@/core/widgets/AppScaffold"
import { PrimaryButton } from "@/core/widgets/Buttons"
import { MascotWidget } from "@/core/widgets/MascotWidget"
import { StatusPill } from "@/core/widgets/StatusPill"
import { CAMPAIGN_PURPOSE_LABELS, CAMPAIGN_PURPOSES, type CampaignPurpose } from "@/data/models/campaign"
import { BackendError } from "@/data/backend/client"
import { cn } from "@/lib/utils"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { toDateInputValue } from "@/core/utils/date"

const PURPOSES: Array<{ value: CampaignPurpose; hint: string }> = CAMPAIGN_PURPOSES.map((value) => ({
  value,
  hint:
    value === "appointment"
      ? "Confirm or book slots"
      : value === "newLead"
        ? "First call to new leads"
        : value === "followUp"
          ? "Check back with waiting customers"
          : value === "payment"
            ? "Collect pending payments"
            : "Anything else you need",
}))

export function StartCallingScreen() {
  const { state, dispatch, repositories } = useApp()
  const { back, navigate } = useRouter()

  const [purpose, setPurpose] = React.useState<CampaignPurpose>("appointment")
  const [timing, setTiming] = React.useState<"now" | "scheduled">("now")
  const [scheduledFor, setScheduledFor] = React.useState(toDateInputValue(new Date(Date.now() + 86_400_000)))
  const [busy, setBusy] = React.useState(false)
  const [error, setError] = React.useState<string | null>(null)

  const callable = state.data.contacts.filter(
    (contact) => contact.status !== "notInterested" && contact.status !== "booked"
  )

  async function handleStart() {
    setBusy(true)
    setError(null)
    try {
      const draft = {
        purpose,
        timing,
        scheduledFor: timing === "scheduled" ? scheduledFor : undefined,
        contactIds: callable.map((contact) => contact.id),
      }

      // The backend creates the round and, when live, starts the provider
      // campaign that actually places the calls.
      const campaign = await repositories.campaigns.startCampaign(draft)

      if (timing === "scheduled") {
        dispatch({
          type: "setToast",
          message: `Saved for ${scheduledFor}. Shampy will start on time.`,
        })
        navigate(ROUTES.calls)
        return
      }

      navigate(ROUTES.campaign(campaign.id), { replace: true })
    } catch (error) {
      // Friendly message only — provider errors are never shown raw.
      setError(
        error instanceof BackendError
          ? error.message
          : "Something went wrong. Please try again."
      )
    } finally {
      setBusy(false)
    }
  }

  return (
    <AppScaffold title="Start calling" onBack={back} contentClassName="pt-4">
      <section className="flex items-center gap-4 rounded-3xl border border-blue/20 bg-blue-soft p-5">
        <MascotWidget state="calling" size="md" />
        <div className="min-w-0 flex-1">
          <p className="text-caption font-bold tracking-wide text-[#2A55D6] uppercase">
            Ready to call
          </p>
          <p className="text-[30px] leading-none font-extrabold tracking-tight text-ink">
            {callable.length}
          </p>
          <p className="text-caption mt-0.5 text-[#2A55D6]">
            {callable.length === 1 ? "customer" : "customers"} in your list
          </p>
        </div>
      </section>

      <section className="mt-6">
        <SectionHeader title="What is this round for?" />
        <div className="flex flex-col gap-2.5">
          {PURPOSES.map((item) => {
            const active = purpose === item.value
            return (
              <button
                key={item.value}
                type="button"
                aria-pressed={active}
                onClick={() => setPurpose(item.value)}
                className={cn(
                  "min-tap flex items-center gap-3.5 rounded-3xl border-2 px-4 py-3.5 text-left transition-all active:scale-[0.99]",
                  active ? "border-brand bg-brand-soft" : "border-border/70 bg-card"
                )}
              >
                <span
                  className={cn(
                    "flex size-10 shrink-0 items-center justify-center rounded-2xl",
                    active ? "bg-brand text-white" : "bg-secondary text-ink-soft"
                  )}
                >
                  <PhoneCall className="size-5" aria-hidden />
                </span>
                <span className="min-w-0 flex-1">
                  <span className="block text-[15px] font-bold text-ink">
                    {CAMPAIGN_PURPOSE_LABELS[item.value]}
                  </span>
                  <span className="text-caption block text-ink-soft">{item.hint}</span>
                </span>
                {active && <StatusPill tone="green">Selected</StatusPill>}
              </button>
            )
          })}
        </div>
      </section>

      <section className="mt-6">
        <SectionHeader title="When should Shampy call?" />
        <Surface className="flex flex-col gap-4">
          <div className="grid grid-cols-2 gap-2.5">
            <button
              type="button"
              aria-pressed={timing === "now"}
              onClick={() => setTiming("now")}
              className={cn(
                "min-tap flex flex-col items-center gap-1.5 rounded-2xl border-2 py-3.5 transition active:scale-[0.98]",
                timing === "now" ? "border-brand bg-brand-soft" : "border-border/70 bg-card"
              )}
            >
              <Zap className={cn("size-5", timing === "now" ? "text-brand" : "text-ink-soft")} aria-hidden />
              <span className="text-[14px] font-bold text-ink">Now</span>
            </button>
            <button
              type="button"
              aria-pressed={timing === "scheduled"}
              onClick={() => setTiming("scheduled")}
              className={cn(
                "min-tap flex flex-col items-center gap-1.5 rounded-2xl border-2 py-3.5 transition active:scale-[0.98]",
                timing === "scheduled" ? "border-brand bg-brand-soft" : "border-border/70 bg-card"
              )}
            >
              <CalendarClock
                className={cn("size-5", timing === "scheduled" ? "text-brand" : "text-ink-soft")}
                aria-hidden
              />
              <span className="text-[14px] font-bold text-ink">Schedule</span>
            </button>
          </div>

          {timing === "scheduled" && (
            <div className="flex flex-col gap-2">
              <Label htmlFor="scheduled-date" className="text-caption font-bold text-ink">
                Pick a date
              </Label>
              <Input
                id="scheduled-date"
                type="date"
                value={scheduledFor}
                onChange={(event) => setScheduledFor(event.target.value)}
                className="h-12 rounded-2xl text-[15px]"
              />
            </div>
          )}
        </Surface>
      </section>

      {error && (
        <p className="text-caption mt-4 rounded-2xl bg-coral-soft px-3.5 py-2.5 font-semibold text-[#C93B3B]" role="alert">
          {error}
        </p>
      )}

      <div className="mt-6">
        <PrimaryButton
          size="lg"
          icon={<PhoneCall />}
          onClick={handleStart}
          loading={busy}
          disabled={callable.length === 0}
        >
          {timing === "now" ? "Start calling" : "Schedule calling"}
        </PrimaryButton>
        <p className="text-[12px] mt-3 text-center font-medium text-ink-soft">
          {BRAND.employeeName} calls each customer, notes the outcome and updates your pipeline
          automatically.
        </p>
      </div>
    </AppScaffold>
  )
}
