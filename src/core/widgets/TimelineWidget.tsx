import { CalendarCheck, CheckCircle2, MessageCircle, PhoneCall, Sparkles } from "lucide-react"

import { cn } from "@/lib/utils"
import { formatElapsed } from "@/core/utils/date"
import type { TimelineEntry } from "@/data/models/contact"

const KIND_STYLE: Record<
  TimelineEntry["kind"],
  { icon: React.ComponentType<{ className?: string }>; className: string }
> = {
  call: { icon: PhoneCall, className: "bg-blue-soft text-blue" },
  status: { icon: CheckCircle2, className: "bg-brand-soft text-brand" },
  message: { icon: MessageCircle, className: "bg-brand-soft text-brand" },
  created: { icon: Sparkles, className: "bg-purple-soft text-purple" },
  appointment: { icon: CalendarCheck, className: "bg-brand-soft text-brand" },
}

export function TimelineWidget({ entries }: { entries: TimelineEntry[] }) {
  if (entries.length === 0) {
    return (
      <p className="text-body rounded-3xl border border-dashed border-border bg-card p-5 text-center text-ink-soft">
        Nothing here yet. Activity will appear after the first call.
      </p>
    )
  }

  return (
    <ol className="relative space-y-0">
      {entries.map((entry, index) => {
        const style = KIND_STYLE[entry.kind]
        const Icon = style.icon
        const last = index === entries.length - 1

        return (
          <li key={entry.id} className="flex gap-3">
            <div className="flex flex-col items-center">
              <span
                className={cn(
                  "flex size-9 shrink-0 items-center justify-center rounded-full [&_svg]:size-[18px]",
                  style.className
                )}
                aria-hidden
              >
                <Icon />
              </span>
              {!last && <span className="w-px flex-1 bg-border" aria-hidden />}
            </div>
            <div className={cn("min-w-0 flex-1", last ? "pb-0" : "pb-5")}>
              <p className="text-[15px] font-bold text-ink">{entry.label}</p>
              {entry.detail && (
                <p className="text-caption mt-0.5 text-ink-soft">{entry.detail}</p>
              )}
              <p className="text-[12px] mt-1 font-semibold text-ink-soft/70">
                {formatElapsed(entry.at)}
              </p>
            </div>
          </li>
        )
      })}
    </ol>
  )
}
