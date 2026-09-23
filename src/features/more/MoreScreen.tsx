import {
  BarChart3,
  Bell,
  Building2,
  CreditCard,
  HelpCircle,
  LogOut,
  Phone,
  Sparkles,
} from "lucide-react"

import { BRAND } from "@/core/constants/brand"
import { ROUTES } from "@/app/routes"
import { useRouter } from "@/app/router"
import { useApp } from "@/core/state/AppStoreProvider"
import { AppScaffold, SectionHeader } from "@/core/widgets/AppScaffold"
import { BottomNavBar } from "@/core/widgets/BottomNavBar"
import { SettingsRow, SwitchRow } from "@/core/widgets/SettingsRow"
import { MascotWidget } from "@/core/widgets/MascotWidget"
import { SecondaryButton } from "@/core/widgets/Buttons"
import { BUSINESS_CATEGORY_META } from "@/data/models/business"
import { NOTIFICATION_LABELS } from "@/data/models/account"

export function MoreScreen() {
  const { state, dispatch, derived } = useApp()
  const { navigate } = useRouter()
  const stats = derived.dashboardStats

  async function handleLogOut() {
    dispatch({ type: "setSession", session: null })
    dispatch({ type: "setToast", message: "You have been logged out" })
    navigate(ROUTES.welcome, { replace: true })
  }

  return (
    <AppScaffold
      title="More"
      contentClassName="pt-4"
      footer={<BottomNavBar badges={{ followUps: stats.followUpsDue, calls: stats.callsActive }} />}
    >
      <section className="flex items-center gap-4 rounded-3xl border border-border/70 bg-card p-5 shadow-card">
        <MascotWidget state="settings" size="md" />
        <div className="min-w-0 flex-1">
          <p className="text-[17px] font-bold text-ink">{state.business.name}</p>
          <p className="text-caption truncate text-ink-soft">
            {BUSINESS_CATEGORY_META[state.business.category].label} · {state.business.phone}
          </p>
          <p className="text-caption mt-1.5 font-semibold text-brand">
            {state.subscription.planLabel} plan · active
          </p>
        </div>
      </section>

      <section className="mt-6">
        <SectionHeader title="Your setup" />
        <div className="flex flex-col gap-2.5">
          <SettingsRow
            icon={<Building2 />}
            tone="green"
            label="Business"
            description="Name, category and phone"
            onClick={() => navigate(ROUTES.business)}
          />
          <SettingsRow
            icon={<Sparkles />}
            tone="purple"
            label={`AI employee`}
            description={`${state.aiEmployee.name} · ${state.aiEmployee.settings.language} voice`}
            onClick={() => navigate(ROUTES.aiEmployee)}
          />
          <SettingsRow
            icon={<Phone />}
            tone="blue"
            label="Phone number"
            description="The number customers call"
            onClick={() => navigate(ROUTES.phoneNumber)}
          />
        </div>
      </section>

      <section className="mt-6">
        <SectionHeader title="Account" />
        <div className="flex flex-col gap-2.5">
          <SettingsRow
            icon={<Bell />}
            tone="amber"
            label="Notifications"
            description="What Shampy should tell you about"
            onClick={() => navigate(ROUTES.notifications)}
          />
          <SettingsRow
            icon={<CreditCard />}
            tone="green"
            label="Subscription"
            rightText={`\u20B9${state.subscription.pricePerMonth.toLocaleString("en-IN")}/mo`}
            onClick={() => navigate(ROUTES.subscription)}
          />
          <SettingsRow
            icon={<BarChart3 />}
            tone="blue"
            label="Usage"
            description={`${stats.totalCalls} calls this cycle`}
            onClick={() => navigate(ROUTES.usage)}
          />
        </div>
      </section>

      <section className="mt-6">
        <SectionHeader title="Help" />
        <div className="flex flex-col gap-2.5">
          <SettingsRow
            icon={<HelpCircle />}
            tone="neutral"
            label="Help & support"
            description={BRAND.supportEmail}
            onClick={() => dispatch({ type: "setToast", message: "Our team will call you back" })}
          />
        </div>
      </section>

      <section className="mt-6">
        <SectionHeader title="Quick toggles" />
        <div className="flex flex-col gap-2.5">
          <SwitchRow
            icon={<Sparkles />}
            tone="purple"
            label="Auto follow-ups"
            description="Shampy creates follow-ups after each call"
            checked={state.aiEmployee.settings.followUpAutomation}
            onCheckedChange={(value) =>
              dispatch({ type: "updateAiSettings", patch: { followUpAutomation: value } })
            }
          />
          <SwitchRow
            icon={<Bell />}
            tone="amber"
            label={NOTIFICATION_LABELS.bookings.label}
            description={NOTIFICATION_LABELS.bookings.description}
            checked={state.notifications.bookings}
            onCheckedChange={() => dispatch({ type: "toggleNotification", channel: "bookings" })}
          />
        </div>
      </section>

      <div className="mt-7">
        <SecondaryButton
          tone="coral"
          icon={<LogOut />}
          onClick={handleLogOut}
        >
          Log out
        </SecondaryButton>
        <p className="text-[12px] mt-4 text-center font-medium text-ink-soft/70">
          {BRAND.productNameUpper} · demo build
        </p>
      </div>
    </AppScaffold>
  )
}
