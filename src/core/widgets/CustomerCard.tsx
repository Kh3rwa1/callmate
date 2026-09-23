import { CalendarCheck, ChevronRight, PhoneCall } from "lucide-react"

import { cn } from "@/lib/utils"
import { formatAppointment, formatElapsed } from "@/core/utils/date"
import type { Contact } from "@/data/models/contact"
import { AvatarImage } from "@/core/widgets/MetricCard"
import { CustomerStatusBadge } from "@/core/widgets/CustomerStatusBadge"

/** Compact inline action used inside customer, call and follow-up cards. */
export function CardActionButton({
  label,
  tone = "green",
  icon,
  onClick,
}: {
  label: string
  tone?: "green" | "blue" | "neutral"
  icon?: React.ReactNode
  onClick: (event: React.MouseEvent) => void
}) {
  const toneClass =
    tone === "green"
      ? "bg-brand-soft text-[#0E8F56]"
      : tone === "blue"
        ? "bg-blue-soft text-[#2A55D6]"
        : "bg-secondary text-ink"

  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        "inline-flex min-tap items-center gap-1.5 rounded-2xl px-3.5 py-2 text-[13px] font-bold transition active:scale-[0.97] [&_svg]:size-4",
        toneClass
      )}
    >
      {icon}
      {label}
    </button>
  )
}

export function ContactAvatar({
  contact,
  size = "md",
}: {
  contact: Contact
  size?: "sm" | "md" | "lg" | "xl"
}) {
  return <AvatarImage name={contact.name} color={contact.avatarColor} size={size} />
}

/**
 * The customer row used by Pipeline, Home attention lists and Follow-ups. The
 * `action` slot keeps each caller in control of its single primary action.
 */
export function CustomerCard({
  contact,
  onClick,
  action,
  trailing,
  highlight,
  className,
}: {
  contact: Contact
  onClick?: () => void
  action?: React.ReactNode
  trailing?: React.ReactNode
  highlight?: string
  className?: string
}) {
  const nextLine = contact.appointment
    ? formatAppointment(contact.appointment.date, contact.appointment.time)
    : contact.lastCallAt
      ? `Last call ${formatElapsed(contact.lastCallAt)}`
      : "Not called yet"

  return (
    <div
      className={cn(
        "rounded-3xl border border-border/70 bg-card p-4 shadow-card transition-all",
        onClick && "cursor-pointer hover:border-brand/30 active:scale-[0.99]",
        className
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
      <div className="flex items-start gap-3">
        <ContactAvatar contact={contact} />
        <div className="min-w-0 flex-1">
          <div className="flex items-start justify-between gap-2">
            <div className="min-w-0">
              <p className="truncate text-[16px] font-bold text-ink">{contact.name}</p>
              <p className="text-caption truncate text-ink-soft">{contact.service}</p>
            </div>
            {onClick && !trailing && (
              <ChevronRight className="mt-0.5 size-5 shrink-0 text-ink-soft/60" aria-hidden />
            )}
            {trailing}
          </div>

          <div className="mt-2.5 flex flex-wrap items-center gap-2">
            <CustomerStatusBadge status={contact.status} />
            {highlight && (
              <span className="text-caption rounded-full bg-secondary px-2.5 py-1 text-ink-soft">
                {highlight}
              </span>
            )}
          </div>

          <p className="text-caption mt-2.5 flex items-center gap-1.5 text-ink-soft">
            {contact.appointment ? (
              <CalendarCheck className="size-4 shrink-0" aria-hidden />
            ) : (
              <PhoneCall className="size-4 shrink-0" aria-hidden />
            )}
            {nextLine}
          </p>
        </div>
      </div>

      {action && (
        <div className="mt-3.5 flex items-center gap-2 border-t border-border/60 pt-3.5">{action}</div>
      )}
    </div>
  )
}
