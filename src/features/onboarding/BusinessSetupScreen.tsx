import * as React from "react"
import {
  ArrowRight,
  Building2,
  Briefcase,
  Scissors,
  Stethoscope,
  Store,
  Utensils,
  type LucideIcon,
} from "lucide-react"

import { cn } from "@/lib/utils"
import { BRAND } from "@/core/constants/brand"
import { BUSINESS_CATEGORIES, BUSINESS_CATEGORY_META, type BusinessCategory } from "@/data/models/business"
import { ROUTES } from "@/app/routes"
import { useRouter } from "@/app/router"
import { useApp } from "@/core/state/AppStoreProvider"
import { MascotWidget } from "@/core/widgets/MascotWidget"
import { PrimaryButton } from "@/core/widgets/Buttons"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"

const CATEGORY_ICONS: Record<BusinessCategory, LucideIcon> = {
  clinic: Stethoscope,
  coaching: Building2,
  salon: Scissors,
  realEstate: Briefcase,
  restaurant: Utensils,
  other: Store,
}

const CATEGORY_TONE: Record<BusinessCategory, string> = {
  clinic: "border-brand bg-brand-soft",
  coaching: "border-blue bg-blue-soft",
  salon: "border-purple bg-purple-soft",
  realEstate: "border-amber bg-amber-soft",
  restaurant: "border-coral bg-coral-soft",
  other: "border-border bg-secondary",
}

const ICON_TONE: Record<BusinessCategory, string> = {
  clinic: "text-brand",
  coaching: "text-blue",
  salon: "text-purple",
  realEstate: "text-[#B47B00]",
  restaurant: "text-coral",
  other: "text-ink",
}

export function BusinessSetupScreen() {
  const { navigate } = useRouter()
  const { dispatch } = useApp()

  const [category, setCategory] = React.useState<BusinessCategory>("clinic")
  const [name, setName] = React.useState("")
  const [phone, setPhone] = React.useState("")
  const [error, setError] = React.useState<string | null>(null)

  function handleContinue() {
    if (!name.trim()) {
      setError("Please enter your business name")
      return
    }
    if (phone.replace(/\D/g, "").length < 10) {
      setError("Please enter a valid phone number")
      return
    }
    setError(null)
    dispatch({
      type: "setBusiness",
      business: {
        name: name.trim(),
        category,
        phone: phone.trim(),
        ownerName: "",
      },
      onboardingComplete: true,
    })
    navigate(ROUTES.home, { replace: true })
  }

  return (
    <div className="flex min-h-svh flex-col bg-canvas px-6 pt-[max(2rem,env(safe-area-inset-top))] pb-[max(1.75rem,env(safe-area-inset-bottom))]">
      <button
        type="button"
        onClick={() => navigate(ROUTES.welcome)}
        className="text-caption min-tap self-start font-bold text-ink-soft"
      >
        Back
      </button>

      <div className="mx-auto w-full max-w-sm flex-1 pt-4 pb-6">
        <div className="flex items-center gap-3">
          <MascotWidget state="writing" size="sm" />
          <div>
            <h1 className="text-hero text-ink">Tell us about your business</h1>
            <p className="text-caption mt-0.5 text-ink-soft">
              Two minutes and {BRAND.employeeName} is ready
            </p>
          </div>
        </div>

        <fieldset className="mt-6">
          <legend className="text-caption mb-2.5 font-bold text-ink">What kind of business?</legend>
          <div className="grid grid-cols-2 gap-2.5">
            {BUSINESS_CATEGORIES.map((item) => {
              const Icon = CATEGORY_ICONS[item]
              const selected = category === item
              return (
                <button
                  key={item}
                  type="button"
                  aria-pressed={selected}
                  onClick={() => setCategory(item)}
                  className={cn(
                    "flex min-tap items-center gap-2.5 rounded-3xl border-2 px-3.5 py-3.5 text-left transition-all active:scale-[0.98]",
                    selected ? CATEGORY_TONE[item] : "border-border/70 bg-card"
                  )}
                >
                  <Icon
                    className={cn("size-5 shrink-0", selected ? ICON_TONE[item] : "text-ink-soft")}
                    aria-hidden
                  />
                  <span className="text-[14px] font-bold text-ink">
                    {BUSINESS_CATEGORY_META[item].label}
                  </span>
                </button>
              )
            })}
          </div>
        </fieldset>

        <div className="mt-6 flex flex-col gap-4">
          <div className="flex flex-col gap-2">
            <Label htmlFor="business-name" className="text-caption font-bold text-ink">
              Business name
            </Label>
            <Input
              id="business-name"
              value={name}
              onChange={(event) => setName(event.target.value)}
              placeholder={BUSINESS_CATEGORY_META[category].label === "Clinic" ? "Sunrise Dental Clinic" : "Your business name"}
              className="h-13 rounded-2xl text-[15px]"
            />
          </div>

          <div className="flex flex-col gap-2">
            <Label htmlFor="business-phone" className="text-caption font-bold text-ink">
              Business phone
            </Label>
            <Input
              id="business-phone"
              type="tel"
              inputMode="tel"
              value={phone}
              onChange={(event) => setPhone(event.target.value)}
              placeholder="+91 98300 41022"
              className="h-13 rounded-2xl text-[15px]"
            />
            <p className="text-[12px] font-medium text-ink-soft">
              Customers will reach {BRAND.employeeName} on this number.
            </p>
          </div>
        </div>

        {error && (
          <p className="text-caption mt-4 rounded-2xl bg-coral-soft px-3.5 py-2.5 font-semibold text-[#C93B3B]" role="alert">
            {error}
          </p>
        )}
      </div>

      <div className="mx-auto w-full max-w-sm">
        <PrimaryButton size="lg" icon={<ArrowRight />} onClick={handleContinue}>
          Continue
        </PrimaryButton>
      </div>
    </div>
  )
}
