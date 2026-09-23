import { ChevronRight } from "lucide-react"

import { cn } from "@/lib/utils"
import { Switch } from "@/components/ui/switch"

const TONE_BG = {
  green: "bg-brand-soft text-brand",
  blue: "bg-blue-soft text-blue",
  purple: "bg-purple-soft text-purple",
  amber: "bg-amber-soft text-[#B47B00]",
  coral: "bg-coral-soft text-coral",
  neutral: "bg-secondary text-ink",
} as const

export type SettingsTone = keyof typeof TONE_BG

export function SettingsRow({
  icon,
  label,
  description,
  tone = "neutral",
  onClick,
  rightText,
  showChevron = true,
  className,
}: {
  icon?: React.ReactNode
  label: string
  description?: string
  tone?: SettingsTone
  onClick?: () => void
  rightText?: string
  showChevron?: boolean
  className?: string
}) {
  const interactive = Boolean(onClick)

  return (
    <button
      type="button"
      onClick={onClick}
      disabled={!interactive}
      className={cn(
        "flex min-tap w-full items-center gap-3.5 rounded-3xl border border-border/70 bg-card px-4 py-3.5 text-left shadow-card transition-all",
        interactive && "active:scale-[0.99] hover:border-brand/30",
        className
      )}
    >
      {icon && (
        <span
          className={cn(
            "flex size-11 shrink-0 items-center justify-center rounded-2xl [&_svg]:size-5",
            TONE_BG[tone]
          )}
          aria-hidden
        >
          {icon}
        </span>
      )}
      <span className="min-w-0 flex-1">
        <span className="block truncate text-[15px] font-bold text-ink">{label}</span>
        {description && (
          <span className="text-caption block truncate text-ink-soft">{description}</span>
        )}
      </span>
      {rightText && (
        <span className="text-caption shrink-0 font-semibold text-ink-soft">{rightText}</span>
      )}
      {showChevron && interactive && (
        <ChevronRight className="size-5 shrink-0 text-ink-soft/60" aria-hidden />
      )}
    </button>
  )
}

export function SwitchRow({
  icon,
  label,
  description,
  tone = "neutral",
  checked,
  onCheckedChange,
}: {
  icon?: React.ReactNode
  label: string
  description?: string
  tone?: SettingsTone
  checked: boolean
  onCheckedChange: (value: boolean) => void
}) {
  return (
    <div className="flex items-center gap-3.5 rounded-3xl border border-border/70 bg-card px-4 py-3.5 shadow-card">
      {icon && (
        <span
          className={cn(
            "flex size-11 shrink-0 items-center justify-center rounded-2xl [&_svg]:size-5",
            TONE_BG[tone]
          )}
          aria-hidden
        >
          {icon}
        </span>
      )}
      <div className="min-w-0 flex-1">
        <p className="truncate text-[15px] font-bold text-ink">{label}</p>
        {description && <p className="text-caption text-ink-soft">{description}</p>}
      </div>
      <Switch
        checked={checked}
        onCheckedChange={onCheckedChange}
        aria-label={label}
        className="data-[state=checked]:bg-brand"
      />
    </div>
  )
}
