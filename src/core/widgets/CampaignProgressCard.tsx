import * as React from "react"
import { PhoneCall } from "lucide-react"

import { cn } from "@/lib/utils"

/** Large circular progress ring used on the campaign screen. */
export function ProgressRing({
  value,
  total,
  size = 220,
  strokeWidth = 14,
  label,
  sublabel,
}: {
  value: number
  total: number
  size?: number
  strokeWidth?: number
  label: string
  sublabel: string
}) {
  const radius = (size - strokeWidth) / 2
  const circumference = 2 * Math.PI * radius
  const ratio = total === 0 ? 0 : Math.min(1, value / total)
  const dash = circumference * ratio

  return (
    <div
      className="relative flex items-center justify-center"
      style={{ width: size, height: size }}
      role="progressbar"
      aria-valuemin={0}
      aria-valuemax={total}
      aria-valuenow={value}
      aria-label={`${value} of ${total} calls completed`}
    >
      <svg width={size} height={size} className="-rotate-90">
        <circle
          cx={size / 2}
          cy={size / 2}
          r={radius}
          fill="none"
          stroke="#E8EDF3"
          strokeWidth={strokeWidth}
        />
        <circle
          cx={size / 2}
          cy={size / 2}
          r={radius}
          fill="none"
          stroke="url(#campaign-ring)"
          strokeWidth={strokeWidth}
          strokeLinecap="round"
          strokeDasharray={`${dash} ${circumference}`}
          style={{ transition: "stroke-dasharray 700ms cubic-bezier(0.22,1,0.36,1)" }}
        />
        <defs>
          <linearGradient id="campaign-ring" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0%" stopColor="#18C97A" />
            <stop offset="100%" stopColor="#4C7DFF" />
          </linearGradient>
        </defs>
      </svg>

      <div className="absolute inset-0 flex flex-col items-center justify-center">
        <span className="text-caption font-bold tracking-wide text-ink-soft uppercase">
          {sublabel}
        </span>
        <span className="text-[40px] leading-none font-extrabold tracking-tight text-ink">
          {label}
        </span>
      </div>
    </div>
  )
}

export function CampaignStatGrid({
  items,
}: {
  items: Array<{ label: string; value: number; tone: "green" | "purple" | "amber" | "coral" }>
}) {
  const toneClass = {
    green: "bg-brand-soft text-[#0E8F56]",
    purple: "bg-purple-soft text-[#6D3BE0]",
    amber: "bg-amber-soft text-[#8A5A00]",
    coral: "bg-coral-soft text-[#C93B3B]",
  } as const

  return (
    <div className="grid grid-cols-2 gap-2.5">
      {items.map((item) => (
        <div key={item.label} className={cn("rounded-3xl p-4", toneClass[item.tone])}>
          <p className="text-[26px] leading-none font-extrabold">{item.value}</p>
          <p className="text-caption mt-1.5 font-bold opacity-90">{item.label}</p>
        </div>
      ))}
    </div>
  )
}

const CONFETTI_COLORS = ["#18C97A", "#4C7DFF", "#8B5CF6", "#FFC857", "#FF6B6B"]

/** Short, tasteful celebration used on successful call outcomes. */
export function Confetti({ pieces = 18 }: { pieces?: number }) {
  const confetti = React.useMemo(
    () =>
      Array.from({ length: pieces }).map((_, index) => ({
        id: index,
        left: Math.random() * 100,
        delay: Math.random() * 0.5,
        drift: `${Math.round((Math.random() - 0.5) * 120)}px`,
        color: CONFETTI_COLORS[index % CONFETTI_COLORS.length],
        size: 6 + Math.round(Math.random() * 6),
      })),
    [pieces]
  )

  return (
    <div
      className="pointer-events-none absolute inset-x-0 top-0 z-10 h-64 overflow-hidden"
      aria-hidden
    >
      {confetti.map((piece) => (
        <span
          key={piece.id}
          className="absolute top-0 rounded-sm"
          style={{
            left: `${piece.left}%`,
            width: piece.size,
            height: piece.size,
            backgroundColor: piece.color,
            animation: `confetti-drop 1.9s ease-in ${piece.delay}s forwards`,
            ["--drift" as string]: piece.drift,
          }}
        />
      ))}
    </div>
  )
}

export function LiveCallIndicator({ label = "Live now" }: { label?: string }) {
  return (
    <span className="inline-flex items-center gap-1.5 rounded-full bg-blue-soft px-3 py-1 text-caption font-bold text-[#2A55D6]">
      <PhoneCall className="size-3.5" aria-hidden />
      {label}
    </span>
  )
}
