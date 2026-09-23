/**
 * Single source of truth for product identity. Renaming the product or the AI
 * employee here updates every screen, document title and message template.
 */
export const BRAND = {
  productName: "Callmate AI",
  productNameUpper: "CALLMATE AI",
  employeeName: "Shampy",
  tagline: "Your AI employee is ready.",
  taglineSupport: "Call customers. Follow up. Book more.",
  currencySymbol: "\u20B9",
  supportEmail: "help@callmate.ai",
  domain: "callmate.ai",
} as const

/**
 * The brand palette. Each colour carries a fixed meaning across the app so
 * status is never expressed by colour alone — always paired with an icon and a
 * label. Keep in sync with the CSS custom properties in src/index.css.
 */
export const PALETTE = {
  green: "#18C97A",
  blue: "#4C7DFF",
  purple: "#8B5CF6",
  yellow: "#FFC857",
  coral: "#FF6B6B",
  background: "#F8FAFC",
  ink: "#172033",
  inkSoft: "#6B7280",
  white: "#FFFFFF",
} as const

export const BRAND_STORAGE_KEY = "callmate"
