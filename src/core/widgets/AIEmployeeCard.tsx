import { Activity, PhoneCall } from "lucide-react"

import { BRAND } from "@/core/constants/brand"
import { MascotWidget } from "@/core/widgets/MascotWidget"
import { SecondaryButton } from "@/core/widgets/Buttons"

/** The AI employee card that sits at the top of Home. */
export function AIEmployeeCard({
  active,
  activeCalls,
  onViewActivity,
}: {
  active: boolean
  activeCalls: number
  onViewActivity: () => void
}) {
  return (
    <section
      className="relative overflow-hidden rounded-[28px] border border-purple/15 bg-gradient-to-br from-purple-soft via-card to-blue-soft p-5 shadow-raised"
      aria-label={`${BRAND.employeeName}, your AI employee`}
    >
      <div className="flex items-start gap-4">
        <MascotWidget state="calling" size="md" label={`${BRAND.employeeName} is working`} />

        <div className="min-w-0 flex-1 pt-1">
          <p className="text-caption font-bold tracking-wide text-purple uppercase">
            AI employee
          </p>
          <h2 className="text-hero mt-0.5 text-ink">{BRAND.employeeName}</h2>

          <span className="mt-2 inline-flex items-center gap-1.5 rounded-full bg-card/90 px-2.5 py-1 text-[12px] font-bold text-[#0E8F56] shadow-card">
            <span className="relative flex size-2">
              {active && (
                <span className="absolute inline-flex size-2 animate-ping rounded-full bg-brand opacity-70" />
              )}
              <span className="relative inline-flex size-2 rounded-full bg-brand" />
            </span>
            {active ? "Working" : "Paused"}
          </span>
        </div>
      </div>

      <div className="mt-4 flex items-center gap-4 rounded-2xl bg-card/85 px-4 py-3">
        <span className="flex items-center gap-2 text-ink">
          <PhoneCall className="size-5 text-blue" aria-hidden />
          <span className="text-[22px] leading-none font-extrabold">{activeCalls}</span>
        </span>
        <span className="text-caption text-ink-soft">
          {activeCalls === 1 ? "call active now" : "calls active now"}
        </span>
      </div>

      <SecondaryButton
        className="mt-3.5 border-purple/20 bg-card/90"
        icon={<Activity className="size-5 text-purple" />}
        onClick={onViewActivity}
      >
        View activity
      </SecondaryButton>
    </section>
  )
}
