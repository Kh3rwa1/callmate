import { ArrowRight, Lock } from "lucide-react"

import { BRAND } from "@/core/constants/brand"
import { MascotWidget } from "@/core/widgets/MascotWidget"
import { PrimaryButton, SecondaryButton } from "@/core/widgets/Buttons"
import { useRouter } from "@/app/router"
import { ROUTES } from "@/app/routes"
import { StatusPill } from "@/core/widgets/StatusPill"

export function WelcomeScreen() {
  const { navigate } = useRouter()

  return (
    <div className="relative flex min-h-svh flex-col justify-between overflow-hidden bg-canvas px-6 pt-[max(2rem,env(safe-area-inset-top))] pb-[max(1.75rem,env(safe-area-inset-bottom))]">
      <div
        className="pointer-events-none absolute -top-32 -right-24 size-80 rounded-full bg-purple-soft opacity-70 blur-2xl"
        aria-hidden
      />
      <div
        className="pointer-events-none absolute -bottom-28 -left-24 size-80 rounded-full bg-brand-soft opacity-70 blur-2xl"
        aria-hidden
      />

      <div className="relative flex items-center justify-between">
        <span className="text-title text-ink">{BRAND.productNameUpper}</span>
        <StatusPill tone="purple" size="sm" icon={<Lock className="size-3.5" />}>
          Private &amp; secure
        </StatusPill>
      </div>

      <div className="relative flex flex-col items-center text-center">
        <MascotWidget state="happy" size="lg" animationEnabled label={`${BRAND.employeeName}, your AI employee`} />
        <h1 className="text-display mt-6 max-w-xs text-ink">{BRAND.tagline}</h1>
        <p className="text-body mt-3 max-w-xs text-ink-soft">{BRAND.taglineSupport}</p>

        <div className="mt-7 flex w-full max-w-sm flex-col gap-3">
          <div className="rounded-3xl border border-border/70 bg-card p-4 text-left shadow-card">
            <p className="text-caption font-bold tracking-wide text-purple uppercase">
              Meet {BRAND.employeeName}
            </p>
            <p className="text-body mt-1 text-ink">
              {BRAND.employeeName} answers your calls, follows up on WhatsApp and books customers
              while you run the shop.
            </p>
          </div>
        </div>
      </div>

      <div className="relative mx-auto flex w-full max-w-sm flex-col gap-3">
        <PrimaryButton
          size="lg"
          icon={<ArrowRight />}
          onClick={() => navigate(ROUTES.onboardingBusiness)}
        >
          Get started
        </PrimaryButton>
        <SecondaryButton onClick={() => navigate(ROUTES.login)}>Log in</SecondaryButton>
      </div>
    </div>
  )
}
