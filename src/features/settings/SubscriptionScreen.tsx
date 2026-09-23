import { BarChart3, CreditCard, MessageCircle, Sparkles, Timer } from "lucide-react"

import { ROUTES } from "@/app/routes"
import { useRouter } from "@/app/router"
import { useApp } from "@/core/state/AppStoreProvider"
import { AppScaffold, SectionHeader, Surface } from "@/core/widgets/AppScaffold"
import { SettingsRow } from "@/core/widgets/SettingsRow"
import { PrimaryButton, SecondaryButton } from "@/core/widgets/Buttons"
import { StatusPill } from "@/core/widgets/StatusPill"

export function SubscriptionScreen() {
  const { state, dispatch } = useApp()
  const { back, navigate } = useRouter()
  const { subscription } = state

  return (
    <AppScaffold title="Subscription" onBack={back} contentClassName="pt-4">
      <Surface className="flex flex-col gap-3">
        <StatusPill tone="green" size="md">Active</StatusPill>
        <p className="text-[30px] leading-none font-extrabold tracking-tight text-ink">
          {subscription.planLabel}
        </p>
        <p className="text-body text-ink-soft">
          {`\u20B9${subscription.pricePerMonth.toLocaleString("en-IN")} per month · renews ${subscription.renewsOn}`}
        </p>
      </Surface>

      <section className="mt-6">
        <SectionHeader title="Included in your plan" />
        <div className="flex flex-col gap-2.5">
          <SettingsRow
            icon={<Timer />}
            tone="blue"
            label="Calling minutes"
            rightText={`${subscription.minutesIncluded.toLocaleString("en-IN")}/mo`}
            showChevron={false}
          />
          <SettingsRow
            icon={<MessageCircle />}
            tone="green"
            label="WhatsApp messages"
            rightText="Unlimited"
            showChevron={false}
          />
          <SettingsRow
            icon={<Sparkles />}
            tone="purple"
            label="AI employee"
            rightText="Unlimited"
            showChevron={false}
          />
        </div>
      </section>

      <div className="mt-6 flex flex-col gap-2.5">
        <PrimaryButton
          tone="dark"
          icon={<CreditCard />}
          onClick={() =>
            dispatch({ type: "setToast", message: "Our team will help you change plans" })
          }
        >
          Change plan
        </PrimaryButton>
        <SecondaryButton icon={<BarChart3 />} onClick={() => navigate(ROUTES.usage)}>
          See this month's usage
        </SecondaryButton>
      </div>
    </AppScaffold>
  )
}
