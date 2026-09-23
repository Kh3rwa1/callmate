import * as React from "react"
import { ArrowRight, Mail, Lock } from "lucide-react"

import { BRAND } from "@/core/constants/brand"
import { ROUTES } from "@/app/routes"
import { useRouter } from "@/app/router"
import { useApp } from "@/core/state/AppStoreProvider"
import { DEMO_BUSINESS } from "@/data/services/contactFactory"
import { MascotWidget } from "@/core/widgets/MascotWidget"
import { PrimaryButton } from "@/core/widgets/Buttons"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"

export function LoginScreen() {
  const { navigate } = useRouter()
  const { auth, dispatch } = useApp()

  const [email, setEmail] = React.useState("owner@sunrisedental.in")
  const [password, setPassword] = React.useState("callmate")
  const [error, setError] = React.useState<string | null>(null)
  const [busy, setBusy] = React.useState(false)

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault()
    setBusy(true)
    setError(null)
    try {
      const session = await auth.signIn({ email, password })
      dispatch({ type: "setSession", session })
      dispatch({ type: "setBusiness", business: DEMO_BUSINESS, onboardingComplete: true })
      navigate(ROUTES.home, { replace: true })
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Something went wrong. Please try again.")
    } finally {
      setBusy(false)
    }
  }

  return (
    <form
      onSubmit={handleSubmit}
      className="flex min-h-svh flex-col bg-canvas px-6 pt-[max(2rem,env(safe-area-inset-top))] pb-[max(1.75rem,env(safe-area-inset-bottom))]"
    >
      <button
        type="button"
        onClick={() => navigate(ROUTES.welcome)}
        className="text-caption min-tap self-start font-bold text-ink-soft"
      >
        Back
      </button>

      <div className="mx-auto flex w-full max-w-sm flex-1 flex-col justify-center gap-6 py-8">
        <div className="flex flex-col items-center text-center">
          <MascotWidget state="idle" size="md" />
          <h1 className="text-hero mt-4 text-ink">Welcome back</h1>
          <p className="text-body mt-1.5 text-ink-soft">
            Log in to see what {BRAND.employeeName} has been doing.
          </p>
        </div>

        <div className="flex flex-col gap-4 rounded-3xl border border-border/70 bg-card p-5 shadow-card">
          <div className="flex flex-col gap-2">
            <Label htmlFor="email" className="text-caption font-bold text-ink">
              Email
            </Label>
            <div className="relative">
              <Mail className="pointer-events-none absolute top-1/2 left-3.5 size-4.5 -translate-y-1/2 text-ink-soft" aria-hidden />
              <Input
                id="email"
                type="email"
                autoComplete="email"
                value={email}
                onChange={(event) => setEmail(event.target.value)}
                className="h-13 rounded-2xl pl-11 text-[15px]"
                placeholder="you@business.in"
                aria-invalid={Boolean(error)}
              />
            </div>
          </div>

          <div className="flex flex-col gap-2">
            <Label htmlFor="password" className="text-caption font-bold text-ink">
              Password
            </Label>
            <div className="relative">
              <Lock className="pointer-events-none absolute top-1/2 left-3.5 size-4.5 -translate-y-1/2 text-ink-soft" aria-hidden />
              <Input
                id="password"
                type="password"
                autoComplete="current-password"
                value={password}
                onChange={(event) => setPassword(event.target.value)}
                className="h-13 rounded-2xl pl-11 text-[15px]"
                placeholder="Your password"
                aria-invalid={Boolean(error)}
              />
            </div>
          </div>

          {error && (
            <p className="text-caption rounded-2xl bg-coral-soft px-3.5 py-2.5 font-semibold text-[#C93B3B]" role="alert">
              {error}
            </p>
          )}

          <PrimaryButton type="submit" size="lg" icon={<ArrowRight />} loading={busy}>
            Log in
          </PrimaryButton>

          <p className="text-[12px] text-center font-medium text-ink-soft">
            This is a demo sign-in. Any email and a 6-character password will work.
          </p>
        </div>
      </div>
    </form>
  )
}
