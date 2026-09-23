import * as React from "react"
import { cn } from "@/lib/utils"

type AppScaffoldProps = {
  title?: string
  /** Small line under the title, used for business name or summary. */
  subtitle?: string
  onBack?: () => void
  /** Right-side header content, such as an icon action. */
  action?: React.ReactNode
  children: React.ReactNode
  /** Bottom navigation renders outside this component, per route. */
  footer?: React.ReactNode
  /** Floating action button slot, positioned above the footer. */
  floating?: React.ReactNode
  contentClassName?: string
  headerClassName?: string
  /** Renders the title larger, for primary screens. */
  size?: "default" | "hero"
  /** Hide the header entirely for immersive screens. */
  hideHeader?: boolean
}

function BackButton({ onBack }: { onBack: () => void }) {
  return (
    <button
      type="button"
      onClick={onBack}
      aria-label="Go back"
      className="flex size-11 shrink-0 items-center justify-center rounded-full bg-card text-ink shadow-card transition active:scale-95"
    >
      <svg viewBox="0 0 24 24" className="size-5" fill="none" stroke="currentColor" strokeWidth={2.4} strokeLinecap="round" strokeLinejoin="round" aria-hidden>
        <path d="M15 18l-6-6 6-6" />
      </svg>
    </button>
  )
}

/**
 * The page frame shared by every screen: safe margins, a soft header and a
 * scrolling body. Keeping this in one place is what makes the app feel
 * consistent rather than assembled screen by screen.
 */
export function AppScaffold({
  title,
  subtitle,
  onBack,
  action,
  children,
  footer,
  floating,
  contentClassName,
  headerClassName,
  size = "default",
  hideHeader = false,
}: AppScaffoldProps) {
  return (
    <div className="relative flex min-h-svh flex-col bg-canvas">
      {!hideHeader && (
        <header
          className={cn(
            "safe-top sticky top-0 z-20 border-b border-border/60 bg-canvas/85 px-5 pt-4 pb-3 backdrop-blur-md",
            headerClassName
          )}
        >
          <div className="mx-auto flex w-full max-w-[560px] items-center gap-3">
            {onBack && <BackButton onBack={onBack} />}
            <div className="min-w-0 flex-1">
              {title && (
                <h1
                  className={cn(
                    "truncate text-ink",
                    size === "hero" ? "text-hero" : "text-title"
                  )}
                >
                  {title}
                </h1>
              )}
              {subtitle && (
                <p className="text-caption truncate text-ink-soft">{subtitle}</p>
              )}
            </div>
            {action}
          </div>
        </header>
      )}

      <main
        className={cn(
          "mx-auto w-full max-w-[560px] flex-1 px-5 pt-4",
          footer ? "pb-6" : "pb-10",
          contentClassName
        )}
      >
        {children}
      </main>

      {floating && (
        <div
          className={cn(
            "pointer-events-none sticky bottom-0 z-20 mx-auto w-full max-w-[560px] px-5",
            footer ? "pb-3" : "pb-6"
          )}
        >
          <div className="pointer-events-auto flex justify-end">{floating}</div>
        </div>
      )}

      {footer}
    </div>
  )
}

export function SectionHeader({
  title,
  action,
  className,
}: {
  title: string
  action?: React.ReactNode
  className?: string
}) {
  return (
    <div className={cn("mb-3 flex items-center justify-between gap-3", className)}>
      <h2 className="text-title text-ink">{title}</h2>
      {action}
    </div>
  )
}

export function Surface({
  className,
  children,
  ...props
}: React.ComponentProps<"div">) {
  return (
    <div
      className={cn(
        "rounded-3xl border border-border/70 bg-card p-5 shadow-card",
        className
      )}
      {...props}
    >
      {children}
    </div>
  )
}
