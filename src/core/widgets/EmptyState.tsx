import { AlertCircle } from "lucide-react"

import { MascotWidget, type MascotState } from "@/core/widgets/MascotWidget"
import { PrimaryButton, SecondaryButton } from "@/core/widgets/Buttons"

/**
 * Friendly empty, error and success placeholders. Errors never surface raw
 * technical detail — the user sees a calm message and a way forward.
 */
export function EmptyState({
  mascotState = "idle",
  title,
  description,
  actionLabel,
  onAction,
  secondaryLabel,
  onSecondary,
  variant = "empty",
}: {
  mascotState?: MascotState
  title: string
  description?: string
  actionLabel?: string
  onAction?: () => void
  secondaryLabel?: string
  onSecondary?: () => void
  variant?: "empty" | "error" | "success"
}) {
  return (
    <div className="flex flex-col items-center gap-4 rounded-3xl border border-dashed border-border bg-card px-6 py-9 text-center shadow-card">
      <MascotWidget state={variant === "error" ? "confused" : mascotState} size="lg" />

      {variant === "error" && (
        <span className="text-caption inline-flex items-center gap-1.5 rounded-full bg-coral-soft px-3 py-1 font-bold text-[#C93B3B]">
          <AlertCircle className="size-4" aria-hidden />
          Something went wrong
        </span>
      )}

      <div className="flex flex-col gap-1.5">
        <h3 className="text-title text-ink">{title}</h3>
        {description && <p className="text-body text-ink-soft">{description}</p>}
      </div>

      {(actionLabel || secondaryLabel) && (
        <div className="mt-1 flex w-full max-w-xs flex-col gap-2.5">
          {actionLabel && onAction && <PrimaryButton onClick={onAction}>{actionLabel}</PrimaryButton>}
          {secondaryLabel && onSecondary && (
            <SecondaryButton onClick={onSecondary}>{secondaryLabel}</SecondaryButton>
          )}
        </div>
      )}
    </div>
  )
}

export function InlineLoader({ label }: { label?: string }) {
  return (
    <div className="flex flex-col items-center gap-3 py-10" role="status" aria-live="polite">
      <MascotWidget state="thinking" size="md" />
      <p className="text-caption text-ink-soft">{label ?? "One moment…"}</p>
    </div>
  )
}
