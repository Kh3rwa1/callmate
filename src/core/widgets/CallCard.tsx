import { ChevronRight, Clock, PhoneCall, PhoneMissed } from "lucide-react"

import { cn } from "@/lib/utils"
import { formatClockTime, formatElapsed } from "@/core/utils/date"
import { CALL_OUTCOME_META, CALL_STATUS_META, type Call } from "@/data/models/call"
import type { Contact } from "@/data/models/contact"
import { StatusPill, type Tone } from "@/core/widgets/StatusPill"
import { AvatarImage } from "@/core/widgets/MetricCard"

export function CallCard({
  call,
  contact,
  onClick,
}: {
  call: Call
  contact: Contact | undefined
  onClick?: () => void
}) {
  const statusMeta = CALL_STATUS_META[call.status]
  const outcomeMeta = call.outcome ? CALL_OUTCOME_META[call.outcome] : null
  const live = call.status === "calling" || call.status === "connected"

  return (
    <div
      className={cn(
        "flex items-center gap-3 rounded-3xl border border-border/70 bg-card p-4 shadow-card transition-all",
        onClick && "cursor-pointer active:scale-[0.99] hover:border-brand/30",
        live && "border-blue/30 bg-blue-soft/40"
      )}
      onClick={onClick}
      role={onClick ? "button" : undefined}
      tabIndex={onClick ? 0 : undefined}
      onKeyDown={
        onClick
          ? (event) => {
              if (event.key === "Enter" || event.key === " ") {
                event.preventDefault()
                onClick()
              }
            }
          : undefined
      }
    >
      <div className="relative">
        <AvatarImage
          name={contact?.name ?? "Unknown"}
          color={contact?.avatarColor ?? "#6B7280"}
          size="md"
        />
        {live && (
          <span className="absolute -right-0.5 -bottom-0.5 flex size-5 items-center justify-center rounded-full bg-blue ring-2 ring-card">
            <PhoneCall className="size-3 text-white" aria-hidden />
          </span>
        )}
      </div>

      <div className="min-w-0 flex-1">
        <div className="flex items-center justify-between gap-2">
          <p className="truncate text-[16px] font-bold text-ink">{contact?.name ?? "Unknown"}</p>
          <span className="text-caption shrink-0 text-ink-soft">
            {formatClockTime(call.startedAt)}
          </span>
        </div>

        <div className="mt-2 flex flex-wrap items-center gap-1.5">
          <StatusPill
            tone={statusMeta.tone as Tone}
            icon={
              call.status === "missed" ? (
                <PhoneMissed className="size-3.5" />
              ) : live ? (
                <PhoneCall className="size-3.5" />
              ) : (
                <Clock className="size-3.5" />
              )
            }
          >
            {statusMeta.label}
          </StatusPill>
          {outcomeMeta && <StatusPill tone={outcomeMeta.tone as Tone}>{outcomeMeta.label}</StatusPill>}
        </div>

        <p className="text-caption mt-2 truncate text-ink-soft">
          {live ? "In progress" : call.summary || formatElapsed(call.startedAt)}
        </p>
      </div>

      {onClick && <ChevronRight className="size-5 shrink-0 text-ink-soft/60" aria-hidden />}
    </div>
  )
}
