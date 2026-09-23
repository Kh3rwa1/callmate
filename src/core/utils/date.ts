import {
  endOfDay,
  isSameDay,
  isToday,
  isTomorrow,
  isYesterday,
  parseISO,
  startOfDay,
} from "date-fns"

const timeFormatter = new Intl.DateTimeFormat("en-IN", {
  hour: "numeric",
  minute: "2-digit",
  hour12: true,
})

const dayFormatter = new Intl.DateTimeFormat("en-IN", {
  weekday: "short",
  day: "numeric",
  month: "short",
})

export function parseTimestamp(value: string | null | undefined) {
  if (!value) return null
  const parsed = parseISO(value)
  return Number.isNaN(parsed.getTime()) ? null : parsed
}

/** "Today · 4:00 PM", "Tomorrow · 11:30 AM", "Fri · 2:00 PM" */
export function formatAppointment(date: string, time: string) {
  const parsed = parseISO(date)
  const day = isToday(parsed)
    ? "Today"
    : isTomorrow(parsed)
      ? "Tomorrow"
      : isYesterday(parsed)
        ? "Yesterday"
        : dayFormatter.format(parsed)

  const [hourText, minuteText] = time.split(":")
  const parsedTime = new Date(parsed)
  parsedTime.setHours(Number(hourText ?? 0), Number(minuteText ?? 0), 0, 0)

  return `${day} \u00b7 ${timeFormatter.format(parsedTime)}`
}

/** "Today", "Tomorrow", "Friday", "12 Sep" */
export function formatRelativeDay(date: string | Date) {
  const parsed = typeof date === "string" ? parseISO(date) : date
  if (isToday(parsed)) return "Today"
  if (isTomorrow(parsed)) return "Tomorrow"
  if (isYesterday(parsed)) return "Yesterday"
  return new Intl.DateTimeFormat("en-IN", {
    weekday: parsed.getTime() - Date.now() < 6 * 86_400_000 ? "long" : undefined,
    day: "numeric",
    month: "short",
  }).format(parsed)
}

export function formatClockTime(value: string | Date) {
  const parsed = typeof value === "string" ? parseISO(value) : value
  return timeFormatter.format(parsed)
}

export function isDateToday(value: string) {
  const parsed = parseISO(value)
  return isSameDay(parsed, new Date())
}

export function isUpcomingOrToday(value: string) {
  const parsed = parseISO(value)
  const now = startOfDay(new Date())
  return parsed.getTime() >= now.getTime() && endOfDay(parsed).getTime() >= now.getTime()
}

export function greetingForHour(hour = new Date().getHours()) {
  if (hour < 12) return "Good morning"
  if (hour < 17) return "Good afternoon"
  return "Good evening"
}

/** Elapsed copy for call rows: "Just now", "22 min ago", "3 hrs ago", "Yesterday", "12 Sep" */
export function formatElapsed(value: string | null | undefined) {
  const parsed = parseTimestamp(value)
  if (!parsed) return ""
  const diffMs = Date.now() - parsed.getTime()
  const minutes = Math.round(diffMs / 60_000)
  if (minutes < 2) return "Just now"
  if (minutes < 60) return `${minutes} min ago`
  const hours = Math.round(minutes / 60)
  if (hours < 24) return `${hours} hr${hours === 1 ? "" : "s"} ago`
  if (isYesterday(parsed)) return "Yesterday"
  return dayFormatter.format(parsed)
}

export function toDateInputValue(date: Date) {
  return date.toISOString().slice(0, 10)
}
