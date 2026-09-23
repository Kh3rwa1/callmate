export type NotificationChannel = "calls" | "bookings" | "followUps" | "payments"

export type NotificationSettings = Record<NotificationChannel, boolean>

export const NOTIFICATION_LABELS: Record<
  NotificationChannel,
  { label: string; description: string }
> = {
  calls: {
    label: "Call updates",
    description: "When Shampy finishes a call",
  },
  bookings: {
    label: "New bookings",
    description: "Customers who book an appointment",
  },
  followUps: {
    label: "Follow-up reminders",
    description: "When a follow-up is due today",
  },
  payments: {
    label: "Payments recovered",
    description: "When a pending payment is collected",
  },
}

export type Subscription = {
  plan: "starter" | "growth" | "scale"
  planLabel: string
  pricePerMonth: number
  minutesIncluded: number
  renewsOn: string
  active: boolean
}

export type Usage = {
  minutesUsed: number
  callsMade: number
  whatsappSent: number
  cycleStart: string
}
