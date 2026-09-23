import { BRAND } from "@/core/constants/brand"
import { formatAppointment } from "@/core/utils/date"
import type { Call } from "@/data/models/call"
import type { Business } from "@/data/models/business"
import type { Contact } from "@/data/models/contact"
import { normalizePhone } from "@/lib/utils"

export type WhatsAppContext = {
  contact: Contact
  business: Business
  lastCall?: Call | null
  businessPhone?: string
}

export type WhatsAppMessage = {
  body: string
  variant: number
}

function signature(business: Business) {
  return `\u2014 ${business.name}`
}

function appointmentLine(contact: Contact) {
  if (!contact.appointment) return null
  return formatAppointment(contact.appointment.date, contact.appointment.time)
}

/**
 * Message generation is intentionally template driven and local. When the
 * backend is in place, this becomes a request that returns an AI-written
 * message; the shape of the result does not change.
 */
export function generateMessages(context: WhatsAppContext): WhatsAppMessage[] {
  const { contact, business } = context
  const firstName = contact.name.split(" ")[0]
  const appointment = appointmentLine(contact)
  const sign = signature(business)

  if (appointment && contact.status === "booked") {
    return [
      {
        variant: 0,
        body: `Hi ${firstName} \u{1F44B} Your appointment for ${contact.appointment?.service} is confirmed for ${appointment}. See you then!\n\n${sign}`,
      },
      {
        variant: 1,
        body: `Hello ${firstName}, this is ${business.name}. Quick reminder \u2014 your ${contact.appointment?.service} is booked for ${appointment}. Reply here if you need to change it.\n\n${sign}`,
      },
      {
        variant: 2,
        body: `${firstName}, you're all set! \u{1F389} We've kept ${appointment} for your ${contact.appointment?.service}. Please arrive 10 minutes early.\n\n${sign}`,
      },
    ]
  }

  if (contact.status === "followUp") {
    return [
      {
        variant: 0,
        body: `Hi ${firstName} \u{1F44B} Thank you for your interest in ${contact.service}. Would you like me to book a time that suits you?\n\n${sign}`,
      },
      {
        variant: 1,
        body: `Hello ${firstName}, following up on our call about ${contact.service}. We have slots open this week \u2014 shall I reserve one for you?\n\n${sign}`,
      },
      {
        variant: 2,
        body: `${firstName}, just checking in about ${contact.service}. Reply with a convenient time and we'll confirm it right away.\n\n${sign}`,
      },
    ]
  }

  if (contact.status === "noResponse") {
    return [
      {
        variant: 0,
        body: `Hi ${firstName} \u{1F44B} We tried calling you about ${contact.service}. When is a good time to talk?\n\n${sign}`,
      },
      {
        variant: 1,
        body: `Hello ${firstName}, we couldn't reach you today. Reply here and we'll call you back at your preferred time.\n\n${sign}`,
      },
      {
        variant: 2,
        body: `${firstName}, we're still holding a slot for your ${contact.service}. Let us know a good time to call.\n\n${sign}`,
      },
    ]
  }

  if (contact.status === "recovered") {
    return [
      {
        variant: 0,
        body: `Hi ${firstName} \u{1F64F} Thank you for completing the payment. Your receipt is on its way.\n\n${sign}`,
      },
      {
        variant: 1,
        body: `Thank you ${firstName}! We've received your payment and updated your account. See you soon.\n\n${sign}`,
      },
      {
        variant: 2,
        body: `${firstName}, your payment is confirmed. Thank you for choosing us!\n\n${sign}`,
      },
    ]
  }

  return [
    {
      variant: 0,
      body: `Hi ${firstName} \u{1F44B} This is ${business.name}. Thanks for your interest in ${contact.service}. How can we help you today?\n\n${sign}`,
    },
    {
      variant: 1,
      body: `Hello ${firstName}! We'd love to help with ${contact.service}. Tell us what you need and we'll take it from there.\n\n${sign}`,
    },
    {
      variant: 2,
      body: `${firstName}, thanks for reaching out to ${business.name}. Shall we set up a quick call about ${contact.service}?\n\n${sign}`,
    },
  ]
}

export function pickMessage(messages: WhatsAppMessage[], variant: number) {
  return messages[variant % messages.length].body
}

export interface WhatsAppService {
  /** Produces ready-to-send message drafts for a customer. */
  generateMessage(context: WhatsAppContext, variant?: number): string
  /** Opens WhatsApp with the message pre-filled. Returns false if unavailable. */
  openWhatsApp(phone: string, message: string): boolean
}

/**
 * Uses WhatsApp's documented click-to-chat deep link with a pre-filled body.
 * No unofficial automation and no credentials live in the app.
 */
export function createWhatsAppService(): WhatsAppService {
  return {
    generateMessage(context, variant = 0) {
      const messages = generateMessages(context)
      return pickMessage(messages, variant)
    },

    openWhatsApp(phone, message) {
      const normalized = normalizePhone(phone).replace(/^\+/, "")
      const url = `https://wa.me/${normalized}?text=${encodeURIComponent(message)}`
      const opened = window.open(url, "_blank", "noopener,noreferrer")
      return opened !== null
    },
  }
}

export const WHATSAPP_AI_LABEL = `AI generated by ${BRAND.employeeName}`
