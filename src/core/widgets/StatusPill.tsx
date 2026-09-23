import { cva, type VariantProps } from "class-variance-authority"
import { cn } from "@/lib/utils"

/**
 * Semantic status tone. Tone is always paired with an icon and a text label at
 * the call site so status never depends on colour alone.
 */
const toneVariants = cva(
  "inline-flex items-center gap-1.5 rounded-full font-semibold whitespace-nowrap",
  {
    variants: {
      tone: {
        green: "bg-brand-soft text-[#0E8F56]",
        blue: "bg-blue-soft text-[#2A55D6]",
        purple: "bg-purple-soft text-[#6D3BE0]",
        amber: "bg-amber-soft text-[#8A5A00]",
        coral: "bg-coral-soft text-[#C93B3B]",
        neutral: "bg-secondary text-ink-soft",
      },
      size: {
        sm: "px-2.5 py-1 text-[12px]",
        md: "px-3 py-1.5 text-[13px]",
        lg: "px-3.5 py-2 text-[14px]",
      },
    },
    defaultVariants: { tone: "neutral", size: "sm" },
  }
)

export type Tone = NonNullable<VariantProps<typeof toneVariants>["tone"]>

export function StatusPill({
  tone = "neutral",
  size = "sm",
  icon,
  children,
  className,
}: {
  tone?: Tone
  size?: "sm" | "md" | "lg"
  icon?: React.ReactNode
  children: React.ReactNode
  className?: string
}) {
  return (
    <span className={cn(toneVariants({ tone, size }), className)}>
      {icon}
      {children}
    </span>
  )
}
