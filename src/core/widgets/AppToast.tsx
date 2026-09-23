import { CheckCircle2 } from "lucide-react"

import { cn } from "@/lib/utils"

/** Lightweight inline confirmation, positioned clear of the bottom navigation. */
export function AppToast({ message }: { message: string | null }) {
  return (
    <div
      className={cn(
        "pointer-events-none fixed inset-x-0 bottom-24 z-50 flex justify-center px-5 transition-all duration-300",
        message ? "translate-y-0 opacity-100" : "translate-y-3 opacity-0"
      )}
      role="status"
      aria-live="polite"
    >
      {message && (
        <span className="flex max-w-[90%] items-center gap-2 rounded-full bg-ink px-4 py-3 text-[14px] font-semibold text-white shadow-raised">
          <CheckCircle2 className="size-4 shrink-0 text-brand" aria-hidden />
          {message}
        </span>
      )}
    </div>
  )
}
