import { ChevronRight, Sparkles, MessageCircle, PhoneCall } from "lucide-react"

import { BRAND } from "@/core/constants/brand"
import { greetingForHour, formatRelativeDay } from "@/core/utils/date"
import { ROUTES } from "@/app/routes"
import { useRouter } from "@/app/router"
import { useApp } from "@/core/state/AppStoreProvider"
import { AppScaffold, SectionHeader } from "@/core/widgets/AppScaffold"
import { BottomNavBar } from "@/core/widgets/BottomNavBar"
import { AIEmployeeCard } from "@/core/widgets/AIEmployeeCard"
import { MetricCard } from "@/core/widgets/MetricCard"
import { CustomerCard, CardActionButton } from "@/core/widgets/CustomerCard"
import { MascotWidget } from "@/core/widgets/MascotWidget"
import { EmptyState, InlineLoader } from "@/core/widgets/EmptyState"
import { contactsNeedingAttention } from "@/data/services/stats"
import { formatCompactCurrency } from "@/lib/utils"

export function HomeScreen() {
  const { state, derived, loadingData, loadError, refresh } = useApp()
  const { navigate } = useRouter()
  const { business, data } = state
  const stats = derived.dashboardStats

  const attention = contactsNeedingAttention(data.contacts, 3)
  const todayBookings = data.contacts.filter((contact) => contact.status === "booked").length

  if (loadingData && data.contacts.length === 0) {
    return (
      <AppScaffold hideHeader footer={<BottomNavBar />} contentClassName="pt-6">
        <InlineLoader label={`Waking up ${BRAND.employeeName}…`} />
      </AppScaffold>
    )
  }

  if (loadError && data.contacts.length === 0) {
    return (
      <AppScaffold hideHeader footer={<BottomNavBar />} contentClassName="pt-6">
        <EmptyState
          variant="error"
          title="We couldn't reach your dashboard"
          description={loadError}
          actionLabel="Try again"
          onAction={() => void refresh().catch(() => undefined)}
        />
      </AppScaffold>
    )
  }

  return (
    <AppScaffold
      hideHeader
      footer={
        <BottomNavBar
          badges={{ followUps: stats.followUpsDue, calls: stats.callsActive }}
        />
      }
      contentClassName="pt-6"
    >
      <header className="mb-5 flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="text-[15px] font-semibold text-ink-soft">
            {greetingForHour()} {"\u{1F44B}"}
          </p>
          <h1 className="text-hero mt-0.5 truncate text-ink">{business.name}</h1>
        </div>
        <button
          type="button"
          onClick={() => navigate(ROUTES.aiEmployee)}
          className="flex size-12 shrink-0 items-center justify-center overflow-hidden rounded-2xl border border-border/70 bg-card shadow-card active:scale-95"
          aria-label={`Open ${BRAND.employeeName} settings`}
        >
          <MascotWidget state="idle" size="sm" animationEnabled={false} />
        </button>
      </header>

      <AIEmployeeCard
        active={state.aiEmployee.active}
        activeCalls={stats.callsActive}
        onViewActivity={() => navigate(ROUTES.calls)}
      />

      <div className="mt-4 flex gap-2.5">
        <MetricCard
          value={String(stats.totalCalls)}
          label="Calls"
          tone="blue"
          icon={<PhoneCall />}
        />
        <MetricCard
          value={String(stats.booked)}
          label="Booked"
          tone="green"
          icon={<Sparkles />}
        />
        <MetricCard
          value={formatCompactCurrency(stats.recoveredAmount, BRAND.currencySymbol)}
          label="Recovered"
          tone="purple"
          icon={<MessageCircle />}
        />
      </div>

      <section className="mt-6">
        <SectionHeader
          title="Needs attention"
          action={
            <button
              type="button"
              onClick={() => navigate(ROUTES.pipeline)}
              className="text-caption min-tap inline-flex items-center gap-1 rounded-2xl px-2 font-bold text-brand"
            >
              Pipeline
              <ChevronRight className="size-4" aria-hidden />
            </button>
          }
        />

        {attention.length === 0 ? (
          <EmptyState
            mascotState="happy"
            title="You're all caught up"
            description="Shampy will tell you when a customer needs you."
            actionLabel="Open pipeline"
            onAction={() => navigate(ROUTES.pipeline)}
          />
        ) : (
          <div className="flex flex-col gap-3">
            {attention.map((contact) => {
              const needsWhatsApp = contact.status !== "calling"
              return (
                <CustomerCard
                  key={contact.id}
                  contact={contact}
                  onClick={() => navigate(ROUTES.customer(contact.id))}
                  highlight={
                    contact.appointment
                      ? `Appointment ${formatRelativeDay(contact.appointment.date).toLowerCase()}`
                      : undefined
                  }
                  action={
                    <CardActionButton
                      label={needsWhatsApp ? "WhatsApp" : "View"}
                      tone={needsWhatsApp ? "green" : "blue"}
                      icon={needsWhatsApp ? <MessageCircle /> : <ChevronRight />}
                      onClick={(event) => {
                        event.stopPropagation()
                        navigate(
                          needsWhatsApp ? ROUTES.whatsapp(contact.id) : ROUTES.customer(contact.id)
                        )
                      }}
                    />
                  }
                />
              )
            })}
          </div>
        )}
      </section>

      <div className="mt-6 flex items-center gap-3 rounded-3xl border border-brand/20 bg-brand-soft px-4 py-4">
        <MascotWidget state="celebrating" size="sm" />
        <p className="text-body flex-1 font-semibold text-[#0E8F56]">
          {todayBookings > 0
            ? `\u{1F389} ${BRAND.employeeName} has ${todayBookings} bookings on the calendar`
            : `${BRAND.employeeName} is ready for today's calls`}
        </p>
      </div>
    </AppScaffold>
  )
}
