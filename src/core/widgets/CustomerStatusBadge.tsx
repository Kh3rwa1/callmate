import { cn } from "@/lib/utils"
import { CONTACT_STATUS_META, type ContactStatus } from "@/data/models/contact"
import { StatusPill, type Tone } from "@/core/widgets/StatusPill"
import { StatusIcon } from "@/core/widgets/StatusIcon"

export function CustomerStatusBadge({
  status,
  size = "sm",
  className,
}: {
  status: ContactStatus
  size?: "sm" | "md" | "lg"
  className?: string
}) {
  const meta = CONTACT_STATUS_META[status]
  return (
    <StatusPill
      tone={meta.tone as Tone}
      size={size}
      icon={<StatusIcon status={status} className="size-3.5" />}
      className={cn(className)}
    >
      {meta.label}
    </StatusPill>
  )
}
