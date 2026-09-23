import { Check, MessageCircle, PhoneCall, Wallet } from "lucide-react"

import { cn } from "@/lib/utils"
import { formatRelativeDay } from "@/core/utils/date"
import { FOLLOW_UP_TYPE_META, type FollowUp } from "@/data/models/followUp"
import type { Contact } from "@/data/models/contact"
import { AvatarImage } from "@/core/widgets/MetricCard"
import { CardActionButton } from "@/core/widgets/CustomerCard"
import { StatusPill, type Tone } from "@/core/widgets/StatusPill"

const TYPE_ICON = {
  whatsapp: MessageCircle,
  call: PhoneCall,
  payment: Wallet,
  reminder: Check,
} as const

/**
 * Follow-up rows deliberately expose exactly one primary action, chosen by the
 * follow-up type, so a non-technical user is never unsure what to tap.
 */
export function FollowUpCard({
  followUp,
  contact,
  onOpenContact,
  onPrimaryAction,
}: {
  followUp: FollowUp
  contact: Contact | undefined
  onOpenContact: () => void
  onPrimaryAction: () => void
}) {
  const meta = FOLLOW_UP_TYPE_META[followUp.type]
  const Icon = TYPE_ICON[followUp.type]

  return (
    <div className="rounded-3xl border border-border/70 bg-card p-4 shadow-card">
      <div
        className="flex cursor-pointer items-start gap-3"
        onClick={onOpenContact}
        role="button"
        tabIndex={0}
        onKeyDown={(event) => {
          if (event.key === "Enter" || event.key === " ") {
            event.preventDefault()
            onOpenContact()
          }
        }}
      >
        <AvatarImage
          name={contact?.name ?? "Unknown"}
          color={contact?.avatarColor ?? "#6B7280"}
          size="md"
        />
        <div className="min-w-0 flex-1">
          <p className="truncate text-[16px] font-bold text-ink">{contact?.name ?? "Unknown"}</p>
          <p className="text-caption mt-0.5 truncate text-ink-soft">
            {formatRelativeDay(followUp.dateTime)} · {contact?.service ?? "Customer"}
          </p>
          <p className={cn("text-caption mt-1.5 line-clamp-2", "text-ink-soft/90")}>
            {followUp.message}
          </p>
        </div>
      </div>

      <div className="mt-3.5 flex items-center justify-between gap-2 border-t border-border/60 pt-3.5">
        <StatusPill tone={meta.tone as Tone} icon={<Icon className="size-3.5" />}>
          {meta.label}
        </StatusPill>
        <CardActionButton
          label={followUp.type === "call" || followUp.type === "reminder" ? "Call" : "WhatsApp"}
          tone={followUp.type === "call" || followUp.type === "reminder" ? "blue" : "green"}
          icon={
            followUp.type === "call" || followUp.type === "reminder" ? (
              <PhoneCall />
            ) : (
              <MessageCircle />
            )
          }
          onClick={(event) => {
            event.stopPropagation()
            onPrimaryAction()
          }}
        />
      </div>
    </div>
  )
}
