import * as React from "react"
import { Building2 } from "lucide-react"

import { useRouter } from "@/app/router"
import { useApp } from "@/core/state/AppStoreProvider"
import { AppScaffold, Surface } from "@/core/widgets/AppScaffold"
import { PrimaryButton } from "@/core/widgets/Buttons"
import {
  BUSINESS_CATEGORIES,
  BUSINESS_CATEGORY_META,
  type BusinessCategory,
} from "@/data/models/business"
import { cn } from "@/lib/utils"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"

export function BusinessSettingsScreen() {
  const { state, dispatch } = useApp()
  const { back } = useRouter()

  const [name, setName] = React.useState(state.business.name)
  const [phone, setPhone] = React.useState(state.business.phone)
  const [category, setCategory] = React.useState<BusinessCategory>(state.business.category)

  function save() {
    dispatch({
      type: "setBusiness",
      business: {
        ...state.business,
        name: name.trim() || state.business.name,
        phone: phone.trim() || state.business.phone,
        category,
      },
      onboardingComplete: state.onboardingComplete,
    })
    dispatch({ type: "setToast", message: "Business details saved" })
  }

  return (
    <AppScaffold title="Business" onBack={back} contentClassName="pt-4">
      <Surface className="flex flex-col gap-4">
        <div className="flex flex-col gap-2">
          <Label htmlFor="biz-name" className="text-caption font-bold text-ink">
            Business name
          </Label>
          <Input
            id="biz-name"
            value={name}
            onChange={(event) => setName(event.target.value)}
            className="h-12 rounded-2xl"
          />
        </div>

        <div className="flex flex-col gap-2">
          <Label htmlFor="biz-phone" className="text-caption font-bold text-ink">
            Business phone
          </Label>
          <Input
            id="biz-phone"
            type="tel"
            inputMode="tel"
            value={phone}
            onChange={(event) => setPhone(event.target.value)}
            className="h-12 rounded-2xl"
          />
        </div>

        <fieldset className="flex flex-col gap-2">
          <legend className="text-caption mb-2 font-bold text-ink">Category</legend>
          <div className="grid grid-cols-2 gap-2">
            {BUSINESS_CATEGORIES.map((item) => (
              <button
                key={item}
                type="button"
                aria-pressed={category === item}
                onClick={() => setCategory(item)}
                className={cn(
                  "min-tap rounded-2xl border-2 px-3 text-[14px] font-bold transition active:scale-[0.98]",
                  category === item
                    ? "border-brand bg-brand-soft text-[#0E8F56]"
                    : "border-border/70 bg-card text-ink"
                )}
              >
                {BUSINESS_CATEGORY_META[item].label}
              </button>
            ))}
          </div>
        </fieldset>

        <PrimaryButton onClick={save}>Save changes</PrimaryButton>
      </Surface>

      <div className="mt-5 flex items-center gap-3 rounded-3xl border border-border/70 bg-card p-5 shadow-card">
        <Building2 className="size-5 shrink-0 text-brand" aria-hidden />
        <p className="text-caption text-ink-soft">
          Shampy introduces your business by this name on every call.
        </p>
      </div>
    </AppScaffold>
  )
}
