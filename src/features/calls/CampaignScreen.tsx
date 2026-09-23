import * as React from "react"
import { List, PhoneOff } from "lucide-react"

import { BRAND } from "@/core/constants/brand"
import { ROUTES } from "@/app/routes"
import { useRouter } from "@/app/router"
import { useApp } from "@/core/state/AppStoreProvider"
import { AppScaffold, SectionHeader } from "@/core/widgets/AppScaffold"
import { EmptyState } from "@/core/widgets/EmptyState"
import { PrimaryButton, SecondaryButton, IconButton } from "@/core/widgets/Buttons"
import { MascotWidget } from "@/core/widgets/MascotWidget"
import { CampaignStatGrid, ProgressRing } from "@/core/widgets/CampaignProgressCard"
import { CallCard } from "@/core/widgets/CallCard"
import { StatusPill } from "@/core/widgets/StatusPill"
import { ContactAvatar } from "@/core/widgets/CustomerCard"
import { BackendError } from "@/data/backend/client"

/** How often we ask the backend to advance the round and report progress. */
const TICK_MS = 2600

export function CampaignScreen({ campaignId }: { campaignId: string }) {
  const { state, dispatch, repositories } = useApp()
  const { navigate } = useRouter()

  const campaign = state.data.campaigns.find((item) => item.id === campaignId)
  const running = campaign?.status === "running"
  const advancing = React.useRef(false)

  /**
   * Each tick asks the backend to advance one call. The backend decides what
   * happened — in mock mode it simulates, in live mode the real provider makes
   * the call and its webhook reports back — and we simply re-read the result.
   */
  React.useEffect(() => {
    if (!running) return
    let cancelled = false

    const advance = async () => {
      if (advancing.current) return
      advancing.current = true
      try {
        await repositories.campaigns.advanceCampaign(campaignId)
      } catch (error) {
        if (cancelled) return
        dispatch({
          type: "setToast",
          message:
            error instanceof BackendError
              ? error.message
              : "We couldn't continue the calling round. Please try again.",
        })
      } finally {
        advancing.current = false
      }
    }

    const timer = window.setInterval(advance, TICK_MS)
    return () => {
      cancelled = true
      window.clearInterval(timer)
    }
  }, [running, campaignId, repositories, dispatch])

  // Announce once when the round finishes so the user is not left waiting.
  React.useEffect(() => {
    if (campaign?.status === "completed") {
      dispatch({
        type: "setToast",
        message: `Calling round finished · ${campaign.booked} booked`,
      })
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [campaign?.status])

  if (!campaign) {
    return (
      <AppScaffold title="Calling round">
        <EmptyState
          mascotState="confused"
          title="This round has finished"
          description="Start a new calling round and Shampy will get to work."
          actionLabel="Start calling"
          onAction={() => navigate(ROUTES.startCalling, { replace: true })}
        />
      </AppScaffold>
    )
  }

  const campaignCalls = state.data.calls
    .filter((call) => call.campaignId === campaign.id)
    .slice(0, 4)
  const nextContact = state.data.contacts.find(
    (contact) => contact.id === campaign.contactIds[campaign.completed]
  )

  async function stop() {
    if (!campaign) return
    try {
      await repositories.campaigns.stopCampaign(campaign.id)
      dispatch({ type: "setToast", message: "Calling round stopped" })
      navigate(ROUTES.calls, { replace: true })
    } catch (error) {
      dispatch({
        type: "setToast",
        message:
          error instanceof BackendError
            ? error.message
            : "We couldn't stop the round. Please try again.",
      })
    }
  }

  return (
    <AppScaffold hideHeader contentClassName="pt-[max(1.5rem,env(safe-area-inset-top))]">
      <div className="flex flex-col gap-5">
        <div className="flex items-center justify-between gap-3">
          <div className="min-w-0">
            <StatusPill tone={campaign.status === "running" ? "blue" : "green"} size="md">
              {campaign.status === "running"
                ? "Calling now"
                : campaign.status === "completed"
                  ? "Finished"
                  : "Stopped"}
            </StatusPill>
            <h1 className="text-hero mt-2 text-ink">
              {campaign.status === "running"
                ? `${BRAND.employeeName} is calling`
                : "Calling round"}
            </h1>
            <p className="text-caption mt-0.5 truncate text-ink-soft">
              {campaign.total} customers · {campaign.purpose}
            </p>
          </div>
          <MascotWidget
            state={campaign.status === "running" ? "calling" : "celebrating"}
            size="md"
            label={`${BRAND.employeeName} is working through your list`}
          />
        </div>

        <div className="flex justify-center rounded-3xl border border-border/70 bg-card py-6 shadow-card">
          <ProgressRing
            value={campaign.completed}
            total={campaign.total}
            label={`${campaign.completed} / ${campaign.total}`}
            sublabel="calls done"
          />
        </div>

        {campaign.status === "running" && nextContact && (
          <div className="flex items-center gap-3 rounded-3xl border border-blue/20 bg-blue-soft p-4">
            <ContactAvatar contact={nextContact} size="sm" />
            <div className="min-w-0 flex-1">
              <p className="text-caption font-bold tracking-wide text-[#2A55D6] uppercase">
                Calling now
              </p>
              <p className="text-[15px] truncate font-bold text-ink">{nextContact.name}</p>
            </div>
            <StatusPill tone="blue">Live</StatusPill>
          </div>
        )}

        <CampaignStatGrid
          items={[
            { label: "Booked", value: campaign.booked, tone: "green" },
            { label: "Interested", value: campaign.interested, tone: "purple" },
            { label: "Follow-ups", value: campaign.followUps, tone: "amber" },
            { label: "No answer", value: campaign.noAnswer, tone: "coral" },
          ]}
        />

        {campaignCalls.length > 0 && (
          <section>
            <SectionHeader title="Latest results" />
            <div className="flex flex-col gap-2.5">
              {campaignCalls.map((call) => (
                <CallCard
                  key={call.id}
                  call={call}
                  contact={state.data.contacts.find((contact) => contact.id === call.contactId)}
                  onClick={() => navigate(ROUTES.callResult(call.id))}
                />
              ))}
            </div>
          </section>
        )}

        <div className="flex flex-col gap-2.5">
          <PrimaryButton tone="dark" icon={<List />} onClick={() => navigate(ROUTES.calls)}>
            View calls
          </PrimaryButton>
          {campaign.status === "running" ? (
            <div className="flex items-center gap-3">
              <SecondaryButton tone="coral" icon={<PhoneOff />} onClick={stop}>
                Stop calling
              </SecondaryButton>
              <IconButton label={`${BRAND.employeeName} status`} tone="brand">
                <MascotWidget state="calling" size="sm" animationEnabled={false} />
              </IconButton>
            </div>
          ) : (
            <SecondaryButton
              icon={<PhoneOff />}
              onClick={() => navigate(ROUTES.startCalling, { replace: true })}
            >
              Start a new round
            </SecondaryButton>
          )}
        </div>

        <p className="text-[12px] pb-2 text-center font-medium text-ink-soft">
          {BRAND.employeeName} reports each result as the call finishes and updates your pipeline
          straight away.
        </p>
      </div>
    </AppScaffold>
  )
}
