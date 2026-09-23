import { CheckCircle2, MessageCircle, PhoneCall } from "lucide-react"

import { BRAND } from "@/core/constants/brand"
import { ROUTES } from "@/app/routes"
import { useRouter } from "@/app/router"
import { useApp } from "@/core/state/AppStoreProvider"
import { AppScaffold, SectionHeader } from "@/core/widgets/AppScaffold"
import { EmptyState } from "@/core/widgets/EmptyState"
import { PrimaryButton, SecondaryButton } from "@/core/widgets/Buttons"
import { MascotWidget, type MascotState } from "@/core/widgets/MascotWidget"
import { StatusPill, type Tone } from "@/core/widgets/StatusPill"
import { AvatarImage } from "@/core/widgets/MetricCard"
import { Confetti } from "@/core/widgets/CampaignProgressCard"
import { TimelineWidget } from "@/core/widgets/TimelineWidget"
import { CALL_OUTCOME_META, type CallOutcome } from "@/data/models/call"
import { formatAppointment } from "@/core/utils/date"
import { OUTCOME_HEADLINE } from "@/data/services/callOutcomeService"
import type { MascotState as MascotStateType } from "@/core/widgets/MascotWidget"

const MASCOT_FOR_OUTCOME: Record<CallOutcome, MascotStateType> = {
  booked: "celebrating",
  recovered: "celebrating",
  interested: "happy",
  followUp: "followUp",
  noResponse: "confused",
  notInterested: "confused",
}

export function CallResultScreen({ callId }: { callId: string }) {
  const { state } = useApp()
  const { navigate, back } = useRouter()

  const call = state.data.calls.find((item) => item.id === callId)
  const contact = state.data.contacts.find((item) => item.id === call?.contactId)

  if (!call || !contact) {
    return (
      <AppScaffold title="Call result" onBack={back}>
        <EmptyState
          mascotState="confused"
          title="We couldn't find this call"
          description="Open your call history to see recent results."
          actionLabel="Back to calls"
          onAction={() => navigate(ROUTES.calls, { replace: true })}
        />
      </AppScaffold>
    )
  }

  const outcome: CallOutcome = call.outcome ?? "interested"
  const headline = OUTCOME_HEADLINE[outcome]
  const meta = CALL_OUTCOME_META[outcome]
  const celebrate = outcome === "booked" || outcome === "recovered"
  const appointment = contact.appointment

  const relatedFollowUp = state.data.followUps.find(
    (item) => item.contactId === contact.id && item.status === "pending"
  )

  return (
    <AppScaffold title="Call result" onBack={back} contentClassName="pt-2">
      <section className="relative overflow-hidden rounded-3xl border border-border/70 bg-card px-5 pt-7 pb-6 text-center shadow-raised">
        {celebrate && <Confetti />}

        <MascotWidget state={MASCOT_FOR_OUTCOME[outcome] as MascotState} size="lg" className="mx-auto" />

        <h1 className="text-display mt-4 text-ink">{headline.title}</h1>
        <p className="text-body mt-1.5 text-ink-soft">{headline.note}</p>

        <div className="mt-4 flex flex-wrap items-center justify-center gap-2">
          <StatusPill tone={meta.tone as Tone} size="md" icon={<CheckCircle2 className="size-3.5" />}>
            {meta.label}
          </StatusPill>
          {contact.tags.slice(0, 2).map((tag) => (
            <StatusPill key={tag} tone="neutral" size="md">
              {tag}
            </StatusPill>
          ))}
        </div>
      </section>

      <section className="mt-4 flex items-center gap-4 rounded-3xl border border-border/70 bg-card p-5 shadow-card">
        <AvatarImage name={contact.name} color={contact.avatarColor} size="lg" />
        <div className="min-w-0 flex-1">
          <p className="text-[17px] font-bold text-ink">{contact.name}</p>
          <p className="text-caption text-ink-soft">{contact.service}</p>
          {appointment && (
            <p className="text-[15px] mt-2 font-bold text-brand">
              {formatAppointment(appointment.date, appointment.time)}
            </p>
          )}
        </div>
      </section>

      {call.summary && (
        <section className="mt-4 rounded-3xl border border-purple/20 bg-purple-soft p-5">
          <p className="text-caption font-bold tracking-wide text-purple uppercase">
            What was said
          </p>
          <p className="text-body mt-1.5 text-ink">{call.summary}</p>
        </section>
      )}

      {relatedFollowUp && (
        <section className="mt-4 rounded-3xl border border-amber/30 bg-amber-soft p-5">
          <p className="text-caption font-bold tracking-wide text-[#8A5A00] uppercase">
            Follow-up created
          </p>
          <p className="text-body mt-1.5 text-ink">{relatedFollowUp.message}</p>
        </section>
      )}

      <section className="mt-5">
        <SectionHeader title="Timeline" />
        <TimelineWidget entries={contact.timeline.slice(0, 4)} />
      </section>

      <div className="mt-6 flex flex-col gap-2.5">
        <PrimaryButton
          size="lg"
          icon={<MessageCircle />}
          onClick={() => navigate(ROUTES.whatsapp(contact.id))}
        >
          Send WhatsApp
        </PrimaryButton>
        <SecondaryButton
          icon={<PhoneCall />}
          onClick={() => navigate(ROUTES.calls, { replace: true })}
        >
          Done
        </SecondaryButton>
        <p className="text-[12px] mt-1 text-center font-medium text-ink-soft">
          {`${BRAND.employeeName} has already updated ${contact.name}'s record and your pipeline.`}
        </p>
      </div>
    </AppScaffold>
  )
}
