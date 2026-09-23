export const BUSINESS_CATEGORIES = [
  "clinic",
  "coaching",
  "salon",
  "realEstate",
  "restaurant",
  "other",
] as const
export type BusinessCategory = (typeof BUSINESS_CATEGORIES)[number]

export const BUSINESS_CATEGORY_META: Record<
  BusinessCategory,
  { label: string; serviceHint: string; customersLabel: string; accent: "green" | "blue" | "purple" | "amber" | "coral" }
> = {
  clinic: {
    label: "Clinic",
    serviceHint: "Consultation",
    customersLabel: "Patients",
    accent: "green",
  },
  coaching: {
    label: "Coaching",
    serviceHint: "Demo class",
    customersLabel: "Students",
    accent: "blue",
  },
  salon: {
    label: "Salon",
    serviceHint: "Appointment",
    customersLabel: "Clients",
    accent: "purple",
  },
  realEstate: {
    label: "Real estate",
    serviceHint: "Site visit",
    customersLabel: "Buyers",
    accent: "amber",
  },
  restaurant: {
    label: "Restaurant",
    serviceHint: "Table booking",
    customersLabel: "Guests",
    accent: "coral",
  },
  other: {
    label: "Other",
    serviceHint: "Enquiry",
    customersLabel: "Customers",
    accent: "green",
  },
}

export type Business = {
  name: string
  category: BusinessCategory
  phone: string
  ownerName: string
}

export const AI_VOICES = ["Warm female", "Calm male", "Young female", "Deep male"] as const
export const AI_LANGUAGES = ["Hindi", "English", "Hinglish", "Tamil", "Bengali", "Marathi"] as const
export const AI_CALL_STYLES = ["Friendly", "Professional", "Short and direct"] as const

export type AiEmployeeSettings = {
  voice: (typeof AI_VOICES)[number]
  language: (typeof AI_LANGUAGES)[number]
  callStyle: (typeof AI_CALL_STYLES)[number]
  workingHoursStart: string
  workingHoursEnd: string
  followUpAutomation: boolean
  autoWhatsApp: boolean
}

export type AiEmployee = {
  name: string
  active: boolean
  answeringMode: "inbound" | "outbound" | "both"
  settings: AiEmployeeSettings
}
