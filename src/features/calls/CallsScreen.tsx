import * as React from "react"

import { BRAND } from "@/core/constants/brand"
import { ROUTES } from "@/app/routes"
import { useRouter } from "@/app/router"
import { useApp } from "@/core/state/AppStoreProvider"
import { AppScaffold, SectionHeader } from "@/core/widgets/AppScaffold"
import { BottomNavBar } from "@/core/widgets/BottomNavBar"
import { CallCard } from "@/core/widgets/CallCard"
import { EmptyState, InlineLoader } from "@/core/widgets/EmptyState"
import { FloatingActionButton } from "@/core/widgets/Buttons"
import { MetricCard } from "@/core/widgets/MetricCard"
import { PhoneCall, PhoneMissed, CheckCircle2 } from "lucide-react"
import { cn } from "@/lib/utils"
import type { CallFilter } from "@/data/models/call"

const FILTERS: Array<{ value: CallFilter; label: string }> = [
  { value: "all", label: "All" },
  { value: "active", label: "Active" },
  { value: "completed", label: "Completed" },
  { value: "missed", label: "Missed" },
]

export function CallsScreen() {
  const { state, dispatch, derived, loadingData, loadError, refresh } = useApp()
  const { navigate } = useRouter()
  const { calls } = state.data

  const contactOf = (contactId: string) =>
    state.data.contacts.find((contact) => contact.id === contactId)

  const filtered = React.useMemo(() => {
    const sorted = [...calls].sort((a, b) => b.startedAt.localeCompare(a.startedAt))
    switch (state.callFilter) {
      case "active":
        return sorted.filter((call) => call.status === "calling" || call.status === "connected")
      case "completed":
        return sorted.filter((call) => call.status === "completed")
      case "missed":
        return sorted.filter((call) => call.status === "missed" || call.status === "failed")
      default:
        return sorted
    }
  }, [calls, state.callFilter])

  const stats = derived.dashboardStats

  if (loadingData && calls.length === 0) {
    return (
      <AppScaffold title="Calls" footer={<BottomNavBar />}>
        <InlineLoader label={`Loading ${BRAND.employeeName}'s calls…`} />
      </AppScaffold>
    )
  }

  if (loadError && calls.length === 0) {
    return (
      <AppScaffold title="Calls" footer={<BottomNavBar />}>
        <EmptyState
          variant="error"
          title="We couldn't load your calls"
          description={loadError}
          actionLabel="Try again"
          onAction={() => void refresh().catch(() => undefined)}
        />
      </AppScaffold>
    )
  }

  return (
    <AppScaffold
      title="Calls"
      contentClassName="pt-4"
      footer={<BottomNavBar badges={{ followUps: stats.followUpsDue, calls: stats.callsActive }} />}
      floating={
        <FloatingActionButton
          label="Start calling"
          icon={<PhoneCall />}
          onClick={() => navigate(ROUTES.startCalling)}
        />
      }
    >
      <section className="rounded-3xl border border-border/70 bg-card p-5 shadow-card">
        <p className="text-caption font-bold tracking-wide text-ink-soft uppercase">Today</p>
        <p className="text-[40px] leading-none font-extrabold tracking-tight text-ink">
          {stats.callsToday}
        </p>
        <p className="text-body mt-1 text-ink-soft">
          calls handled by {BRAND.employeeName}
        </p>
      </section>

      <div className="mt-4 flex gap-2.5">
        <MetricCard value={String(stats.callsActive)} label="Active" tone="blue" icon={<PhoneCall />} />
        <MetricCard
          value={String(calls.filter((call) => call.status === "completed").length)}
          label="Completed"
          tone="green"
          icon={<CheckCircle2 />}
        />
        <MetricCard
          value={String(stats.noAnswer)}
          label="Missed"
          tone="coral"
          icon={<PhoneMissed />}
        />
      </div>

      <div className="no-scrollbar -mx-5 mt-5 flex gap-2 overflow-x-auto px-5">
        {FILTERS.map((filter) => {
          const active = state.callFilter === filter.value
          return (
            <button
              key={filter.value}
              type="button"
              aria-pressed={active}
              onClick={() => dispatch({ type: "setCallFilter", filter: filter.value })}
              className={cn(
                "min-tap shrink-0 rounded-full border px-4 text-[14px] font-bold transition-all active:scale-[0.98]",
                active
                  ? "border-brand bg-brand text-white shadow-brand"
                  : "border-border/70 bg-card text-ink-soft"
              )}
            >
              {filter.label}
            </button>
          )
        })}
      </div>

      <section className="mt-5">
        <SectionHeader title={`${filtered.length} ${filtered.length === 1 ? "call" : "calls"}`} />

        {filtered.length === 0 ? (
          <EmptyState
            mascotState="idle"
            title={state.callFilter === "all" ? `Your AI is ready` : "No calls here yet"}
            description={
              state.callFilter === "all"
                ? `${BRAND.employeeName} hasn't made any calls yet. Start a calling round and the results will show up here.`
                : "Try a different filter to see other calls."
            }
            actionLabel="Start calling"
            onAction={() => navigate(ROUTES.startCalling)}
            secondaryLabel={state.callFilter === "all" ? undefined : "Show all calls"}
            onSecondary={
              state.callFilter === "all"
                ? undefined
                : () => dispatch({ type: "setCallFilter", filter: "all" })
            }
          />
        ) : (
          <div className="flex flex-col gap-3">
            {filtered.map((call) => {
              const contact = contactOf(call.contactId)
              const live = call.status === "calling" || call.status === "connected"
              const target = live
                ? ROUTES.liveCall(call.id)
                : call.status === "completed"
                  ? ROUTES.callResult(call.id)
                  : contact
                    ? ROUTES.customer(contact.id)
                    : ROUTES.calls
              return (
                <CallCard
                  key={call.id}
                  call={call}
                  contact={contact}
                  onClick={() => navigate(target)}
                />
              )
            })}
          </div>
        )}
      </section>
    </AppScaffold>
  )
}
