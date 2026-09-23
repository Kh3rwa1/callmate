import {
  CheckCircle2,
  CircleDashed,
  Clock,
  Frown,
  PhoneCall,
  PhoneMissed,
  Sparkles,
  type LucideIcon,
} from "lucide-react"

import type { ContactStatus } from "@/data/models/contact"

/**
 * Status is communicated with colour plus icon plus label everywhere. This maps
 * each state to a distinct shape so it stays readable without colour vision.
 */
const CONTACT_STATUS_ICON: Record<ContactStatus, LucideIcon> = {
  new: CircleDashed,
  calling: PhoneCall,
  followUp: Clock,
  booked: CheckCircle2,
  recovered: Sparkles,
  noResponse: PhoneMissed,
  notInterested: Frown,
}

export function StatusIcon({
  status,
  className,
}: {
  status: ContactStatus
  className?: string
}) {
  const Icon = CONTACT_STATUS_ICON[status]
  return <Icon className={className} strokeWidth={2.6} aria-hidden />
}
