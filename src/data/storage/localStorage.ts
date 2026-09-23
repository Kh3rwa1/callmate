import type { AiEmployee, Business } from "@/data/models/business"
import type { ContactStatus } from "@/data/models/contact"
import type { NotificationSettings } from "@/data/models/account"
import { BRAND_STORAGE_KEY } from "@/core/constants/brand"

export type PersistedShape = {
  onboardingComplete: boolean
  business: Business
  session: { userId: string; email: string; name: string } | null
  selectedStage: ContactStatus
  aiEmployee: AiEmployee
  notifications: NotificationSettings
  customerOverrides: unknown[]
}

type StorageAdapter = {
  read<T>(key: string): T | null
  write(key: string, value: unknown): void
  remove(key: string): void
}

const KEYS = {
  onboarding: "onboarding",
  business: "business",
  selectedStage: "stage",
  ai: "ai-employee",
  notifications: "notifications",
  account: "account",
} as const

/**
 * Thin typed wrapper over localStorage. Only non-sensitive preferences and the
 * demo session live here — never provider credentials.
 */
export function createStorage(): StorageAdapter {
  const scoped = (key: string) => `${BRAND_STORAGE_KEY}:${key}`

  return {
    read<T>(key: string): T | null {
      try {
        const raw = window.localStorage.getItem(scoped(key))
        return raw ? (JSON.parse(raw) as T) : null
      } catch {
        return null
      }
    },
    write(key, value) {
      try {
        window.localStorage.setItem(scoped(key), JSON.stringify(value))
      } catch {
        /* storage unavailable — the app keeps working in memory */
      }
    },
    remove(key) {
      try {
        window.localStorage.removeItem(scoped(key))
      } catch {
        /* no-op */
      }
    },
  }
}

export const STORAGE_KEYS = KEYS

export type AppStorage = StorageAdapter
