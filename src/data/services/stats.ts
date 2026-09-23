import { startOfDay } from "date-fns"

import type { Call } from "@/data/models/call"
import type { Contact, ContactStatus } from "@/data/models/contact"
import type { FollowUp } from "@/data/models/followUp"
import { parseTimestamp } from "@/core/utils/date"

export type DashboardStats = {
  callsToday: number
  callsActive: number
  totalCalls: number
  booked: number
  recoveredAmount: number
  interested: number
  followUpsDue: number
  noAnswer: number
}

export type PipelineCounts = Record<ContactStatus, number>

export function countByStatus(contacts: Contact[]): PipelineCounts {
  const counts: PipelineCounts = {
    new: 0,
    calling: 0,
    followUp: 0,
    booked: 0,
    recovered: 0,
    noResponse: 0,
    notInterested: 0,
  }
  for (const contact of contacts) counts[contact.status] += 1
  return counts
}

function isToday(value: string | null) {
  const parsed = parseTimestamp(value)
  if (!parsed) return false
  return parsed.getTime() >= startOfDay(new Date()).getTime()
}

export function computeDashboardStats(
  contacts: Contact[],
  calls: Call[],
  followUps: FollowUp[]
): DashboardStats {
  return {
    callsToday: calls.filter((call) => isToday(call.startedAt)).length,
    callsActive: calls.filter(
      (call) => call.status === "calling" || call.status === "connected"
    ).length,
    totalCalls: calls.length,
    booked: contacts.filter((contact) => contact.status === "booked").length,
    recoveredAmount: contacts.reduce(
      (sum, contact) => sum + (contact.recoveredAmount ?? 0),
      0
    ),
    interested: contacts.filter((contact) => contact.status === "followUp").length,
    followUpsDue: followUps.filter(
      (item) => item.status === "pending" && isDueSoon(item.dateTime)
    ).length,
    noAnswer: contacts.filter((contact) => contact.status === "noResponse").length,
  }
}

function isDueSoon(dateTime: string) {
  const parsed = parseTimestamp(dateTime)
  if (!parsed) return false
  const endOfTomorrow = startOfDay(new Date()).getTime() + 2 * 86_400_000
  return parsed.getTime() <= endOfTomorrow
}

export function pendingFollowUps(followUps: FollowUp[]) {
  return followUps
    .filter((item) => item.status === "pending")
    .sort((a, b) => a.dateTime.localeCompare(b.dateTime))
}

const ATTENTION_PRIORITY: ContactStatus[] = ["booked", "followUp", "calling", "noResponse"]

export function contactsNeedingAttention(contacts: Contact[], limit = 3) {
  return contacts
    .filter((contact) => ATTENTION_PRIORITY.includes(contact.status))
    .sort(
      (a, b) =>
        ATTENTION_PRIORITY.indexOf(a.status) - ATTENTION_PRIORITY.indexOf(b.status)
    )
    .slice(0, limit)
}
