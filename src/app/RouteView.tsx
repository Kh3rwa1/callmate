import { useRouter } from "@/app/router"
import { matchRoute, ROUTES, type RouteId } from "@/app/routes"
import { useApp } from "@/core/state/AppStoreProvider"
import { MascotWidget } from "@/core/widgets/MascotWidget"
import { WelcomeScreen } from "@/features/welcome/WelcomeScreen"
import { LoginScreen } from "@/features/auth/LoginScreen"
import { BusinessSetupScreen } from "@/features/onboarding/BusinessSetupScreen"
import { HomeScreen } from "@/features/home/HomeScreen"
import { PipelineScreen } from "@/features/pipeline/PipelineScreen"
import { CustomerDetailScreen } from "@/features/customers/CustomerDetailScreen"
import { CallsScreen } from "@/features/calls/CallsScreen"
import { LiveCallScreen } from "@/features/calls/LiveCallScreen"
import { CallResultScreen } from "@/features/calls/CallResultScreen"
import { StartCallingScreen } from "@/features/calls/StartCallingScreen"
import { CampaignScreen } from "@/features/calls/CampaignScreen"
import { FollowUpsScreen } from "@/features/followups/FollowUpsScreen"
import { WhatsAppScreen } from "@/features/whatsapp/WhatsAppScreen"
import { MoreScreen } from "@/features/more/MoreScreen"
import { AiEmployeeScreen } from "@/features/ai/AiEmployeeScreen"
import { BusinessSettingsScreen } from "@/features/settings/BusinessSettingsScreen"
import { PhoneNumberScreen } from "@/features/settings/PhoneNumberScreen"
import { NotificationsScreen } from "@/features/settings/NotificationsScreen"
import { SubscriptionScreen } from "@/features/settings/SubscriptionScreen"
import { UsageScreen } from "@/features/settings/UsageScreen"

/** Routes reachable before onboarding is finished. */
const PUBLIC_ROUTES: RouteId[] = ["welcome", "login", "onboardingBusiness"]

function Splash() {
  return (
    <div className="flex min-h-svh flex-col items-center justify-center gap-4 bg-canvas">
      <MascotWidget state="idle" size="lg" />
      <p className="text-caption font-semibold text-ink-soft">Waking up Shampy…</p>
    </div>
  )
}

function NotFound() {
  const { navigate } = useRouter()
  return (
    <div className="flex min-h-svh flex-col items-center justify-center gap-5 bg-canvas px-8 text-center">
      <MascotWidget state="confused" size="lg" />
      <div>
        <p className="text-title text-ink">This page took a wrong turn</p>
        <p className="text-body mt-1 text-ink-soft">Let's get you back to your dashboard.</p>
      </div>
      <button
        type="button"
        onClick={() => navigate(ROUTES.home, { replace: true })}
        className="min-tap rounded-2xl bg-brand px-6 py-3.5 text-[15px] font-bold text-white shadow-brand"
      >
        Go to home
      </button>
    </div>
  )
}

export function RouteView() {
  const { pathname } = useRouter()
  const { state } = useApp()
  const match = matchRoute(pathname)

  if (!state.hydrated) return <Splash />
  if (!match) return <NotFound />

  // First run: keep the user in the welcome → setup path until it is finished.
  if (!state.onboardingComplete && !PUBLIC_ROUTES.includes(match.id)) {
    return <WelcomeScreen />
  }

  switch (match.id) {
    case "welcome":
      return <WelcomeScreen />
    case "login":
      return <LoginScreen />
    case "onboardingBusiness":
      return <BusinessSetupScreen />

    case "home":
      return <HomeScreen />
    case "pipeline":
      return <PipelineScreen />
    case "customer":
      return <CustomerDetailScreen contactId={match.params.id} />

    case "calls":
      return <CallsScreen />
    case "liveCall":
      return <LiveCallScreen callId={match.params.id} />
    case "callResult":
      return <CallResultScreen callId={match.params.id} />
    case "startCalling":
      return <StartCallingScreen />
    case "campaign":
      return <CampaignScreen campaignId={match.params.id} />

    case "followUps":
      return <FollowUpsScreen />
    case "whatsapp":
      return <WhatsAppScreen contactId={match.params.id} />
    case "more":
      return <MoreScreen />

    case "aiEmployee":
      return <AiEmployeeScreen />
    case "business":
      return <BusinessSettingsScreen />
    case "phoneNumber":
      return <PhoneNumberScreen />
    case "notifications":
      return <NotificationsScreen />
    case "subscription":
      return <SubscriptionScreen />
    case "usage":
      return <UsageScreen />

    default:
      return <NotFound />
  }
}
