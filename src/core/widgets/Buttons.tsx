import * as React from "react"
import { cva, type VariantProps } from "class-variance-authority"

import { cn } from "@/lib/utils"
import { Spinner } from "@/components/ui/spinner"

const primaryButtonVariants = cva(
  "inline-flex min-tap w-full items-center justify-center gap-2 rounded-2xl px-5 text-[15px] font-bold transition-all outline-none focus-visible:ring-2 focus-visible:ring-offset-2 disabled:pointer-events-none disabled:opacity-50 active:scale-[0.98] [&_svg]:size-5 [&_svg]:shrink-0",
  {
    variants: {
      tone: {
        brand: "bg-brand text-primary-foreground shadow-brand hover:bg-brand/92 focus-visible:ring-brand/40",
        blue: "bg-blue text-blue-foreground shadow-[0_10px_24px_rgba(76,125,255,0.28)] hover:bg-blue/92",
        purple: "bg-purple text-purple-foreground shadow-[0_10px_24px_rgba(139,92,246,0.28)] hover:bg-purple/92",
        coral: "bg-coral text-coral-foreground shadow-[0_10px_24px_rgba(255,107,107,0.26)] hover:bg-coral/92",
        dark: "bg-ink text-white hover:bg-ink/90",
      },
      size: {
        md: "h-13 py-3.5",
        lg: "h-14 py-4 text-base",
      },
    },
    defaultVariants: { tone: "brand", size: "md" },
  }
)

export type PrimaryButtonProps = React.ComponentProps<"button"> &
  VariantProps<typeof primaryButtonVariants> & {
    loading?: boolean
    icon?: React.ReactNode
  }

export function PrimaryButton({
  className,
  tone,
  size,
  loading = false,
  icon,
  children,
  disabled,
  ...props
}: PrimaryButtonProps) {
  return (
    <button
      type="button"
      disabled={disabled || loading}
      className={cn(primaryButtonVariants({ tone, size }), className)}
      {...props}
    >
      {loading ? <Spinner className="size-5 text-current" /> : icon}
      {children}
    </button>
  )
}

export function SecondaryButton({
  className,
  icon,
  children,
  tone = "neutral",
  ...props
}: React.ComponentProps<"button"> & {
  icon?: React.ReactNode
  tone?: "neutral" | "brand" | "blue" | "coral"
}) {
  const toneClass =
    tone === "brand"
      ? "text-brand border-brand/25 bg-brand-soft"
      : tone === "blue"
        ? "text-blue border-blue/20 bg-blue-soft"
        : tone === "coral"
          ? "text-coral border-coral/20 bg-coral-soft"
          : "text-ink border-border bg-card"

  return (
    <button
      type="button"
      className={cn(
        "inline-flex min-tap w-full items-center justify-center gap-2 rounded-2xl border px-5 py-3.5 text-[15px] font-semibold transition-all outline-none active:scale-[0.98] disabled:opacity-50 [&_svg]:size-5 [&_svg]:shrink-0",
        toneClass,
        className
      )}
      {...props}
    >
      {icon}
      {children}
    </button>
  )
}

type IconButtonProps = React.ComponentProps<"button"> & {
  label: string
  tone?: "neutral" | "coral" | "blue" | "brand"
  size?: "md" | "lg"
}

export function IconButton({
  label,
  tone = "neutral",
  size = "lg",
  className,
  children,
  ...props
}: IconButtonProps) {
  const toneClass =
    tone === "coral"
      ? "bg-coral text-white shadow-[0_10px_22px_rgba(255,107,107,0.3)]"
      : tone === "blue"
        ? "bg-blue text-white shadow-[0_10px_22px_rgba(76,125,255,0.3)]"
        : tone === "brand"
          ? "bg-brand text-white shadow-brand"
          : "bg-card text-ink border border-border shadow-card"

  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      className={cn(
        "inline-flex shrink-0 items-center justify-center rounded-full transition-all outline-none active:scale-95 [&_svg]:size-6",
        size === "lg" ? "size-14" : "size-11",
        toneClass,
        className
      )}
      {...props}
    >
      {children}
    </button>
  )
}

export function FloatingActionButton({
  label,
  icon,
  onClick,
  tone = "brand",
}: {
  label: string
  icon: React.ReactNode
  onClick: () => void
  tone?: "brand" | "blue"
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        "inline-flex min-tap items-center gap-2 rounded-full px-5 py-3.5 text-[15px] font-bold text-white transition-all active:scale-[0.97] [&_svg]:size-5",
        tone === "brand" ? "bg-brand shadow-brand" : "bg-blue shadow-[0_10px_24px_rgba(76,125,255,0.32)]"
      )}
    >
      {icon}
      {label}
    </button>
  )
}
