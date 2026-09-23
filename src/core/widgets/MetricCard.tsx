import * as React from "react"
import { cn, initialsOf } from "@/lib/utils"

const SIZE = {
  sm: "size-10 text-[13px]",
  md: "size-12 text-[15px]",
  lg: "size-16 text-xl",
  xl: "size-20 text-2xl",
} as const

export function AvatarImage({
  name,
  color,
  size = "md",
  className,
}: {
  name: string
  color: string
  size?: keyof typeof SIZE
  className?: string
}) {
  return (
    <span
      className={cn(
        "inline-flex shrink-0 items-center justify-center rounded-full font-bold text-white select-none",
        SIZE[size],
        className
      )}
      style={{ backgroundColor: color }}
      aria-hidden
    >
      {initialsOf(name)}
    </span>
  )
}

type MetricToneProps = {
  value: string
  label: string
  tone?: "green" | "blue" | "purple" | "amber" | "coral"
  icon?: React.ReactNode
}

const METRIC_TONE = {
  green: "bg-brand-soft text-[#0E8F56]",
  blue: "bg-blue-soft text-[#2A55D6]",
  purple: "bg-purple-soft text-[#6D3BE0]",
  amber: "bg-amber-soft text-[#8A5A00]",
  coral: "bg-coral-soft text-[#C93B3B]",
} as const

/** The three-up number tiles used on Home, Calls and Follow-ups. */
export function MetricCard({ value, label, tone = "green", icon }: MetricToneProps) {
  return (
    <div className="flex flex-1 flex-col gap-2 rounded-3xl border border-border/70 bg-card p-4 shadow-card">
      {icon && (
        <span
          className={cn(
            "inline-flex size-9 items-center justify-center rounded-xl [&_svg]:size-[18px]",
            METRIC_TONE[tone]
          )}
          aria-hidden
        >
          {icon}
        </span>
      )}
      <span className="text-[28px] leading-none font-extrabold tracking-tight text-ink">
        {value}
      </span>
      <span className="text-caption text-ink-soft">{label}</span>
    </div>
  )
}
