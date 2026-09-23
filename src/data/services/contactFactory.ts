import type { Contact } from "@/data/models/contact"

/**
 * Demo business used before onboarding is completed in this browser.
 *
 * The tenant's voice configuration (Sarvam organization, workspace, deployment
 * id, phone number) is NOT here: it lives in the backend database per
 * organization, because the browser must never hold provider identifiers.
 */
export const DEMO_BUSINESS = {
  name: "Sunrise Dental Clinic",
  category: "clinic",
  phone: "+91 98300 41022",
  ownerName: "Dr. Meera Sen",
} as const

export const CATEGORY_DEFAULT_SERVICE: Record<string, string> = {
  clinic: "Consultation",
  coaching: "Demo class",
  salon: "Appointment",
  realEstate: "Site visit",
  restaurant: "Table booking",
  other: "Enquiry",
}

/** A locally-created contact used only until the backend response arrives. */
export function buildOptimisticContact(input: {
  id: string
  name: string
  phone: string
  service: string
}): Contact {
  return {
    id: input.id,
    name: input.name,
    phone: input.phone,
    avatarColor: "#18C97A",
    service: input.service,
    status: "new",
    lastCallAt: null,
    nextFollowUpAt: null,
    appointment: null,
    tags: ["New lead"],
    notes: "",
    createdAt: new Date().toISOString(),
    timeline: [
      {
        id: `${input.id}_created`,
        label: "Added to Callmate",
        detail: "Ready for the first call",
        at: new Date().toISOString(),
        kind: "created",
      },
    ],
  }
}
