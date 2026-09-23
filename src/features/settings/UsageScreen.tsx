import { ROUTES } from "@/app/routes"
import { useRouter } from "@/app/router"
import { useApp } from "@/core/state/AppStoreProvider"
import { AppScaffold, SectionHeader, Surface } from "@/core/widgets/AppScaffold"
import { MascotWidget } from "@/core/widgets/MascotWidget"
import { EmptyState } from "@/core/widgets/EmptyState"
import { cn } from "@/lib/utils"

export function UsageScreen() {
  const { state } = useApp()
  const { back, navigate } = useRouter()
  const { usage, subscription } = state

  const rows = [
    {
      label: "Calling minutes",
      used: usage.minutesUsed,
      total: subscription.minutesIncluded,
      bar: "bg-blue",
    },
    { label: "Calls made", used: usage.callsMade, total: 1500, bar: "bg-brand" },
    { label: "WhatsApp messages", used: usage.whatsappSent, total: 500, bar: "bg-purple" },
  ]

  const minutesRatio = usage.minutesUsed / subscription.minutesIncluded
  const nearlyOut = minutesRatio > 0.8

  return (
    <AppScaffold title="Usage" onBack={back} contentClassName="pt-4">
      <Surface className="flex items-center gap-4">
        <MascotWidget state="thinking" size="md" />
        <div className="min-w-0">
          <p className="text-[15px] font-bold text-ink">This billing cycle</p>
          <p className="text-caption truncate text-ink-soft">Started {usage.cycleStart}</p>
        </div>
      </Surface>

      <section className="mt-6">
        <SectionHeader title="What you've used" />
        <div className="flex flex-col gap-3">
          {rows.map((row) => {
            const percent = Math.min(100, Math.round((row.used / row.total) * 100))
            return (
              <Surface key={row.label} className="flex flex-col gap-3">
                <div className="flex items-center justify-between gap-2">
                  <p className="text-[15px] truncate font-bold text-ink">{row.label}</p>
                  <p className="text-caption shrink-0 font-bold text-ink-soft">
                    {row.used.toLocaleString("en-IN")} / {row.total.toLocaleString("en-IN")}
                  </p>
                </div>
                <div className="h-2.5 w-full overflow-hidden rounded-full bg-secondary">
                  <div
                    className={cn("h-full rounded-full transition-all duration-700", row.bar)}
                    style={{ width: `${percent}%` }}
                  />
                </div>
                <p className="text-[12px] font-semibold text-ink-soft">{percent}% used</p>
              </Surface>
            )
          })}
        </div>
      </section>

      {nearlyOut && (
        <div className="mt-5">
          <EmptyState
            mascotState="confused"
            title="Nearly out of minutes"
            description="You've used most of this month's calling minutes. A bigger plan keeps Shampy calling without a break."
            actionLabel="See plans"
            onAction={() => navigate(ROUTES.subscription)}
          />
        </div>
      )}
    </AppScaffold>
  )
}
