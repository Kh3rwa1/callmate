import { CheckCircle2 } from "lucide-react"

import { BRAND } from "@/core/constants/brand"
import { ROUTES } from "@/app/routes"
import { useRouter } from "@/app/router"
import { useApp } from "@/core/state/AppStoreProvider"
import { AppScaffold, SectionHeader } from "@/core/widgets/AppScaffold"
import { BottomNavBar } from "@/core/widgets/BottomNavBar"
import { FollowUpCard } from "@/core/widgets/FollowUpCard"
import { EmptyState } from "@/core/widgets/EmptyState"
import { MetricCard } from "@/core/widgets/MetricCard"
import { MascotWidget } from "@/core/widgets/MascotWidget"

export function FollowUpsScreen() {
  const { state, derived, repositories } = useApp()
  const { navigate } = useRouter()

  const pending = derived.pendingFollowUpsList
  const contactOf = (contactId: string) =>
    state.data.contacts.find((contact) => contact.id === contactId)

  return (
    <AppScaffold
      title="Follow-ups"
      contentClassName="pt-4"
      footer={
        <BottomNavBar
          badges={{ followUps: pending.length, calls: derived.dashboardStats.callsActive }}
        />
      }
    >
      <section className="flex items-center gap-4 rounded-3xl border border-amber/30 bg-amber-soft p-5">
        <MascotWidget state="followUp" size="md" />
        <div className="min-w-0 flex-1">
          <p className="text-[44px] leading-none font-extrabold tracking-tight text-ink">
            {pending.length}
          </p>
          <p className="text-caption mt-1 font-bold text-[#8A5A00]">
            Customers waiting for attention
          </p>
        </div>
      </section>

      <div className="mt-4 flex gap-2.5">
        <MetricCard
          value={String(derived.dashboardStats.booked)}
          label="Booked"
          tone="green"
          icon={<CheckCircle2 />}
        />
        <MetricCard
          value={String(derived.dashboardStats.interested)}
          label="Warm leads"
          tone="purple"
        />
      </div>

      <section className="mt-6">
        <SectionHeader title="Due next" />

        {pending.length === 0 ? (
          <EmptyState
            mascotState="happy"
            title="You're all caught up 🎉"
            description={`${BRAND.employeeName} will create the next follow-up automatically after each call.`}
            actionLabel="Start calling"
            onAction={() => navigate(ROUTES.startCalling)}
          />
        ) : (
          <div className="flex flex-col gap-3">
            {pending.map((followUp) => (
              <FollowUpCard
                key={followUp.id}
                followUp={followUp}
                contact={contactOf(followUp.contactId)}
                onOpenContact={() => navigate(ROUTES.customer(followUp.contactId))}
                onPrimaryAction={async () => {
                  if (followUp.type === "call") {
                    navigate(ROUTES.startCalling)
                    return
                  }
                  // The backend owns the follow-up queue, so it is closed there.
                  await repositories.followUps.markDone(followUp.id)
                  navigate(ROUTES.whatsapp(followUp.contactId))
                }}
              />
            ))}
          </div>
        )}
      </section>
    </AppScaffold>
  )
}
