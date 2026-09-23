import { clsx, type ClassValue } from "clsx"
import { twMerge } from "tailwind-merge"

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

export function sleep(ms: number) {
  return new Promise<void>((resolve) => setTimeout(resolve, ms))
}

export function formatDuration(totalSeconds: number) {
  const safe = Math.max(0, Math.floor(totalSeconds))
  const minutes = Math.floor(safe / 60)
  const seconds = safe % 60
  return `${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`
}

/** 24500 -> "24.5K", 1280 -> "1.3K", 940 -> "940" */
export function formatCompactNumber(value: number) {
  if (Math.abs(value) >= 1_000_000) {
    return `${(value / 1_000_000).toFixed(1).replace(/\.0$/, "")}M`
  }
  if (Math.abs(value) >= 1000) {
    return `${(value / 1000).toFixed(1).replace(/\.0$/, "")}K`
  }
  return String(value)
}

/** 24500 -> "₹24.5K" */
export function formatCompactCurrency(value: number, symbol = "\u20B9") {
  return `${symbol}${formatCompactNumber(value)}`
}

export function initialsOf(name: string) {
  return name
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part.charAt(0).toUpperCase())
    .join("")
}

export function normalizePhone(phone: string) {
  return phone.replace(/[^\d+]/g, "")
}

export function createId(prefix: string) {
  return `${prefix}_${Math.random().toString(36).slice(2, 9)}`
}
