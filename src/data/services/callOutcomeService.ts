import { createId } from "@/lib/utils"
import { formatAppointment, toDateInputValue } from "@/core/utils/date"
import type { CallOutcome } from "@/data/models/call"
import type { Business } from "@/data/models/business"
import type { Contact, ContactStatus, TimelineEntry } from "@/data/models/contact"
import type { FollowUp } from "@/data/models/followUp"

/** Campaign rounds only ever produce the four outcomes their counters track. */
export type CampaignOutcome = Extract<
  CallOutcome,
  "booked" | "interested" | "followUp" | "noResponse"
>

export const OUTCOME_HEADLINE: Record<CallOutcome, { title: string; note: string }> = {
  booked: { title: "Booked!", note: "Appointment added to the calendar" },
  recovered: { title: "Payment recovered!", note: "The pending amount is cleared" },
  interested: { title: "Interested", note: "Moved to follow up" },
  followUp: { title: "Follow up needed", note: "A reminder was created" },
  noResponse: { title: "No answer", note: "Shampy will try again" },
  notInterested: { title: "Not interested", note: "Moved out of the pipeline" },
}

export const OUTCOME_LABEL: Record<CallOutcome, string> = {
  booked: "Appointment booked",
  interested: "Interested",
  followUp: "Follow up needed",
  recovered: "Payment recovered",
  noResponse: "No answer",
  notInterested: "Not interested",
}

/** Builds the timeline entry that records a finished call. */
export function timelineEntryForCall(
  contact: Contact,
  outcome: CallOutcome,
  summary: string
): TimelineEntry {
  return {
    id: createId("tl"),
    label: OUTCOME_HEADLINE[outcome].title,
    detail: summary || `${contact.name}'s call with Shampy`,
    at: new Date().toISOString(),
    kind: outcome === "booked" || outcome === "recovered" ? "appointment" : "call",
  }
}

/** A booking defaults to tomorrow at 4 PM, which the user can adjust later. */
export function buildAppointmentForBooking(contact: Contact) {
  const tomorrow = new Date(Date.now() + 86_400_000)
  return {
    date: toDateInputValue(tomorrow),
    time: "16:00",
    service: contact.service,
    status: "scheduled" as const,
  }
}

export function buildFollowUpForContact(
  contact: Contact,
  outcome: CallOutcome,
  businessCategory: Business["category"]
): FollowUp {
  const now = new Date()
  const isBooked = outcome === "booked"
  const appointment = isBooked ? buildAppointmentForBooking(contact) : null

  const due = new Date(
    now.getFullYear(),
    now.getMonth(),
    now.getDate() + 1,
    isBooked ? 9 : 10,
    0
  )

  const firstName = contact.name.split(" ")[0]
  const type: FollowUp["type"] = isBooked
    ? "reminder"
    : outcome === "noResponse"
      ? "whatsapp"
      : businessCategory === "clinic"
        ? "call"
        : "whatsapp"

  const message = appointment
    ? `Remind ${firstName} about the appointment on ${formatAppointment(
        appointment.date,
        appointment.time
      )}.`
    : outcome === "noResponse"
      ? `Send ${firstName} a WhatsApp message since the call was not answered.`
      : `Check if ${firstName} is ready for the next step.`

  return {
    id: createId("f"),
    contactId: contact.id,
    dateTime: due.toISOString(),
    type,
    status: "pending",
    message,
  }
}

export function contactStatusForOutcome(outcome: CallOutcome): ContactStatus {
  switch (outcome) {
    case "booked":
      return "booked"
    case "recovered":
      return "recovered"
    case "interested":
    case "followUp":
      return "followUp"
    case "notInterested":
      return "notInterested"
    case "noResponse":
      return "noResponse"
  }
}
