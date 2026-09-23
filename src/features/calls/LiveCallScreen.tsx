import * as React from "react"
import { Info, Mic, MicOff, PhoneOff } from "lucide-react"

import { BRAND } from "@/core/constants/brand"
import { ROUTES } from "@/app/routes"
import { useRouter } from "@/app/router"
import { useApp } from "@/core/state/AppStoreProvider"
import { AppScaffold } from "@/core/widgets/AppScaffold"
import { EmptyState } from "@/core/widgets/EmptyState"
import { IconButton, SecondaryButton } from "@/core/widgets/Buttons"
import { MascotWidget } from "@/core/widgets/MascotWidget"
import { StatusPill } from "@/core/widgets/StatusPill"
import { formatDuration } from "@/lib/utils"
import { CALL_OUTCOME_META, type CallOutcome } from "@/data/models/call"
import { BackendError } from "@/data/backend/client"
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet"

const OUTCOME_OPTIONS: CallOutcome[] = [
  "booked",
  "interested",
  "recovered",
  "followUp",
  "noResponse",
  "notInterested",
]

/**
 * The live call screen.
 *
 * The call itself is placed by the backend (which talks to the voice provider),
 * and the outcome is recorded by the backend too. This screen shows the call in
 * progress and lets the user record what happened — it never invents a business
 * result locally, so the Pipeline always matches the call record.
 *
 * Note: the full transcript is deliberately NOT shown here. It is available from
 * Call Details / the customer screen, which loads it on demand.
 */
export function LiveCallScreen({ callId }: { callId: string }) {
  const { state, dispatch, repositories } = useApp()
  const { navigate, back } = useRouter()

  const [elapsed, setElapsed] = React.useState(0)
  const [muted, setMuted] = React.useState(false)
  const [detailsOpen, setDetailsOpen] = React.useState(false)
  const [finishing, setFinishing] = React.useState(false)

  const call = state.data.calls.find((item) => item.id === callId)
  const contact = state.data.contacts.find((item) => item.id === call?.contactId)

  React.useEffect(() => {
    if (!call) return
    const started = new Date(call.startedAt).getTime()
    const tick = () => setElapsed(Math.max(0, Math.round((Date.now() - started) / 1000)))
    tick()
    const timer = window.setInterval(tick, 1000)
    return () => window.clearInterval(timer)
  }, [call])

  if (!call) {
    return (
      <AppScaffold title="Call" onBack={back}>
        <EmptyState
          mascotState="confused"
          title="This call has ended"
          description="You can find its result in your call history."
          actionLabel="Back to calls"
          onAction={() => navigate(ROUTES.calls, { replace: true })}
        />
      </AppScaffold>
    )
  }

  async function finish(outcome: CallOutcome) {
    if (!call || finishing) return
    setFinishing(true)
    try {
      // The backend records the outcome, moves the customer and creates any
      // follow-up; we then show the result screen from its data.
      await repositories.calls.completeCall(call.id, outcome)
      navigate(ROUTES.callResult(call.id), { replace: true })
    } catch (error) {
      dispatch({
        type: "setToast",
        message:
          error instanceof BackendError
            ? error.message
            : "We couldn't save that result. Please try again.",
      })
      setFinishing(false)
    }
  }

  const connected = elapsed > 4
  const insight = contact?.notes ? INSIGHT_BY_STATUS[contact.status] : "New customer"

  return (
    <AppScaffold
      title="Live call"
      onBack={back}
      hideHeader
      contentClassName="pt-[max(1.5rem,env(safe-area-inset-top))]"
    >
      <div className="flex min-h-[calc(100svh-3rem)] flex-col items-center justify-between pb-4">
        <div className="flex flex-col items-center">
          <StatusPill tone={connected ? "green" : "blue"} size="md">
            {connected ? "Connected" : "Connecting"}
          </StatusPill>
          <MascotWidget
            state={connected ? "happy" : "calling"}
            size="md"
            className="mt-4"
            label={`${BRAND.employeeName} is on a call`}
          />
          <h1 className="text-hero mt-4 text-center text-ink">
            {connected
              ? `Talking to ${contact?.name ?? "customer"}…`
              : `Calling ${contact?.name ?? "customer"}…`}
          </h1>
          <p className="mt-2 text-[40px] leading-none font-extrabold tracking-tight text-ink tabular-nums">
            {formatDuration(elapsed)}
          </p>
          <p className="text-caption mt-1.5 text-ink-soft">{contact?.service ?? "Outbound call"}</p>
        </div>

        <div className="mt-6 w-full rounded-3xl border border-purple/20 bg-purple-soft p-4">
          <p className="text-caption flex items-center gap-1.5 font-bold tracking-wide text-purple uppercase">
            <Info className="size-3.5" aria-hidden />
            {BRAND.employeeName}'s insight
          </p>
          <p className="text-body mt-1.5 font-semibold text-ink">{insight}</p>
        </div>

        <div className="mt-6 w-full">
          <p className="text-caption mb-2.5 text-center font-bold text-ink-soft">
            How did this call go?
          </p>
          <div className="grid grid-cols-2 gap-2.5">
            {OUTCOME_OPTIONS.map((outcome) => (
              <SecondaryButton
                key={outcome}
                disabled={finishing}
                tone={
                  outcome === "booked" || outcome === "recovered"
                    ? "brand"
                    : outcome === "noResponse"
                      ? "coral"
                      : "neutral"
                }
                onClick={() => finish(outcome)}
              >
                {CALL_OUTCOME_META[outcome].label}
              </SecondaryButton>
            ))}
          </div>
        </div>

        <div className="mt-6 flex items-center justify-center gap-6">
          <div className="flex flex-col items-center gap-1.5">
            <IconButton
              label={muted ? "Unmute" : "Mute"}
              tone={muted ? "coral" : "neutral"}
              onClick={() => setMuted((value) => !value)}
            >
              {muted ? <MicOff /> : <Mic />}
            </IconButton>
            <span className="text-[12px] font-semibold text-ink-soft">Mute</span>
          </div>

          <div className="flex flex-col items-center gap-1.5">
            <IconButton
              label="End call"
              tone="coral"
              onClick={() => finish("followUp")}
              className="size-16"
            >
              <PhoneOff />
            </IconButton>
            <span className="text-[12px] font-semibold text-ink-soft">End</span>
          </div>

          <div className="flex flex-col items-center gap-1.5">
            <IconButton label="Call details" onClick={() => setDetailsOpen(true)}>
              <Info />
            </IconButton>
            <span className="text-[12px] font-semibold text-ink-soft">Details</span>
          </div>
        </div>
      </div>

      <Sheet open={detailsOpen} onOpenChange={setDetailsOpen}>
        <SheetContent side="bottom" className="rounded-t-3xl">
          <SheetHeader>
            <SheetTitle className="text-title">Call details</SheetTitle>
            <SheetDescription className="text-caption text-ink-soft">
              What {BRAND.employeeName} knows about this call.
            </SheetDescription>
          </SheetHeader>

          <div className="flex flex-col gap-3 px-4 pb-6">
            <DetailRow label="Customer" value={contact?.name ?? "Unknown"} />
            <DetailRow label="Phone" value={contact?.phone ?? "—"} />
            <DetailRow label="Service" value={contact?.service ?? "—"} />
            <DetailRow label="Duration" value={formatDuration(elapsed)} />
            <DetailRow
              label="Direction"
              value={call.direction === "inbound" ? "Inbound" : "Outbound"}
            />
            {contact?.notes && <DetailRow label="Notes" value={contact.notes} />}
            <SecondaryButton onClick={() => setDetailsOpen(false)}>Close</SecondaryButton>
          </div>
        </SheetContent>
      </Sheet>
    </AppScaffold>
  )
}

function DetailRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-start justify-between gap-4 rounded-2xl bg-secondary px-4 py-3">
      <span className="text-caption font-bold text-ink-soft">{label}</span>
      <span className="text-[14px] max-w-[60%] text-right font-semibold text-ink">{value}</span>
    </div>
  )
}

const INSIGHT_BY_STATUS: Record<string, string> = {
  new: "A brand new enquiry — first conversation is important.",
  calling: "Already in a conversation with Shampy.",
  followUp: "Warm lead. Ask which time works best.",
  booked: "Already booked. Confirm the appointment details.",
  recovered: "Payment collected. Thank the customer.",
  noResponse: "Has not picked up before. Keep it brief.",
  notInterested: "Was not interested earlier.",
}
