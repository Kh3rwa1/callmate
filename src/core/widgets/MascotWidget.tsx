import { cn } from "@/lib/utils"

export type MascotState =
  | "idle"
  | "calling"
  | "thinking"
  | "happy"
  | "celebrating"
  | "followUp"
  | "confused"
  | "writing"
  | "settings"

export type MascotSize = "sm" | "md" | "lg"

const SIZE_PX: Record<MascotSize, number> = {
  sm: 56,
  md: 104,
  lg: 176,
}

const INK = "#172033"
const BODY = "#8B5CF6"
const BODY_DARK = "#7C4DEB"
const FACE = "#FFFFFF"
const GREEN = "#18C97A"
const CORAL = "#FF6B6B"

type MascotWidgetProps = {
  state?: MascotState
  /** Sizes are discrete so the mascot never scales to an odd aspect. */
  size?: MascotSize
  /** Convenience flag for hero placements. */
  doubleSize?: boolean
  smallSize?: boolean
  animationEnabled?: boolean
  className?: string
  label?: string
}

function Eyes({ state }: { state: MascotState }) {
  const closed = state === "happy" || state === "celebrating"

  if (closed) {
    return (
      <g stroke={INK} strokeWidth={3.2} strokeLinecap="round" fill="none">
        <path d="M45 56 q4 -5 8 0" />
        <path d="M67 56 q4 -5 8 0" />
      </g>
    )
  }

  if (state === "confused") {
    return (
      <g>
        <circle cx="49" cy="55" r="3.6" fill={INK} />
        <path d="M64 54 q4 -3 8 2" stroke={INK} strokeWidth={2.6} strokeLinecap="round" fill="none" />
      </g>
    )
  }

  if (state === "thinking") {
    return (
      <g fill={INK}>
        <circle cx="49" cy="53" r="3.6" />
        <circle cx="68" cy="53" r="3.6" />
        <circle cx="50.8" cy="51.6" r="1.1" fill={FACE} />
        <circle cx="69.8" cy="51.6" r="1.1" fill={FACE} />
      </g>
    )
  }

  return (
    <g fill={INK}>
      <circle cx="49" cy="55" r="3.8" />
      <circle cx="68" cy="55" r="3.8" />
      <circle cx="50.4" cy="53.4" r="1.2" fill={FACE} />
      <circle cx="69.4" cy="53.4" r="1.2" fill={FACE} />
    </g>
  )
}

function Mouth({ state }: { state: MascotState }) {
  if (state === "celebrating") {
    return <path d="M52 65 q6 7 13 0 q-6 4 -13 0 z" fill={INK} />
  }
  if (state === "happy") {
    return <path d="M53 64 q5 5 11 0" stroke={INK} strokeWidth={2.8} strokeLinecap="round" fill="none" />
  }
  if (state === "confused") {
    return <path d="M54 65 q4 -3 6 1 q3 -3 6 1" stroke={INK} strokeWidth={2.6} strokeLinecap="round" fill="none" />
  }
  if (state === "thinking" || state === "writing") {
    return <circle cx="60" cy="65" r="2.6" fill={INK} />
  }
  return <path d="M55 64 q4 4 9 0" stroke={INK} strokeWidth={2.6} strokeLinecap="round" fill="none" />
}

function Accessories({ state }: { state: MascotState }) {
  switch (state) {
    case "calling":
      return (
        <g>
          <path
            d="M30 44 q30 -26 60 0"
            stroke={INK}
            strokeWidth={4}
            strokeLinecap="round"
            fill="none"
          />
          <rect x="24" y="40" width="10" height="20" rx="5" fill={INK} />
          <rect x="86" y="40" width="10" height="20" rx="5" fill={INK} />
          <path
            d="M92 74 q14 4 12 20"
            stroke={BODY_DARK}
            strokeWidth={6}
            strokeLinecap="round"
            fill="none"
          />
          <rect x="96" y="92" width="14" height="20" rx="5" fill={GREEN} />
        </g>
      )

    case "celebrating":
      return (
        <g>
          <path d="M20 74 q-8 -12 -2 -22" stroke={BODY_DARK} strokeWidth={6} strokeLinecap="round" fill="none" />
          <path d="M100 74 q8 -12 2 -22" stroke={BODY_DARK} strokeWidth={6} strokeLinecap="round" fill="none" />
          <circle cx="24" cy="34" r="3.4" fill={GREEN} />
          <circle cx="98" cy="30" r="3.4" fill="#FFC857" />
          <circle cx="36" cy="18" r="2.6" fill={CORAL} />
          <circle cx="84" cy="16" r="2.6" fill="#4C7DFF" />
          <circle cx="12" cy="56" r="2.4" fill="#FFC857" />
          <circle cx="108" cy="58" r="2.4" fill={GREEN} />
        </g>
      )

    case "thinking":
      return (
        <g fill={BODY} opacity={0.9}>
          <circle cx="100" cy="34" r="8" />
          <circle cx="90" cy="22" r="5" />
          <circle cx="82" cy="13" r="3" />
        </g>
      )

    case "followUp":
      return (
        <g>
          <path d="M20 74 q-8 -6 -6 -16" stroke={BODY_DARK} strokeWidth={6} strokeLinecap="round" fill="none" />
          <rect x="4" y="58" width="34" height="30" rx="8" fill={FACE} stroke="#E8EDF3" strokeWidth={2} />
          <rect x="4" y="58" width="34" height="9" rx="4" fill="#FFC857" />
          <circle cx="14" cy="76" r="2.4" fill={GREEN} />
          <path d="M20 76 h12" stroke="#C7CDD6" strokeWidth={2.6} strokeLinecap="round" />
          <circle cx="14" cy="83" r="2.4" fill={GREEN} />
          <path d="M20 83 h9" stroke="#C7CDD6" strokeWidth={2.6} strokeLinecap="round" />
        </g>
      )

    case "writing":
      return (
        <g>
          <path d="M100 74 q8 -8 4 -18" stroke={BODY_DARK} strokeWidth={6} strokeLinecap="round" fill="none" />
          <rect x="86" y="52" width="34" height="24" rx="10" fill={GREEN} />
          <path d="M92 76 l-2 8 l9 -8 z" fill={GREEN} />
          <circle cx="95" cy="64" r="2.2" fill="#FFFFFF" />
          <circle cx="103" cy="64" r="2.2" fill="#FFFFFF" />
          <circle cx="111" cy="64" r="2.2" fill="#FFFFFF" />
        </g>
      )

    case "settings":
      return (
        <g>
          <path d="M20 74 q-8 -6 -7 -16" stroke={BODY_DARK} strokeWidth={6} strokeLinecap="round" fill="none" />
          <rect x="2" y="44" width="24" height="38" rx="7" fill={INK} />
          <rect x="5" y="48" width="18" height="27" rx="4" fill="#EEF2F8" />
          <circle cx="14" cy="78" r="2" fill="#8892A4" />
          <circle cx="14" cy="62" r="4.6" fill="none" stroke={BODY} strokeWidth={2.4} />
        </g>
      )

    case "confused":
      return (
        <g>
          <circle cx="102" cy="26" r="7" fill={CORAL} />
          <text x="102" y="31" textAnchor="middle" fontSize="10" fontWeight="700" fill="#FFFFFF">
            ?
          </text>
        </g>
      )

    default:
      return (
        <g stroke={BODY_DARK} strokeWidth={6} strokeLinecap="round" fill="none">
          <path d="M20 74 q-8 -4 -8 -14" />
          <path d="M100 74 q8 -4 8 -14" />
        </g>
      )
  }
}

/**
 * The Shampy mascot. Drawn as vectors so it stays crisp at any size and remains
 * visually identical on every screen. Swap this file for final artwork later
 * without touching any screen.
 */
export function MascotWidget({
  state = "idle",
  size = "md",
  doubleSize = false,
  smallSize = false,
  animationEnabled = true,
  className,
  label,
}: MascotWidgetProps) {
  const resolvedSize: MascotSize = doubleSize ? "lg" : smallSize ? "sm" : size
  const px = SIZE_PX[resolvedSize]

  const glow =
    state === "calling"
      ? "var(--blue)"
      : state === "celebrating" || state === "happy"
        ? GREEN
        : state === "confused"
          ? CORAL
          : state === "followUp"
            ? "var(--amber)"
            : BODY

  const animationClass =
    !animationEnabled
      ? ""
      : state === "calling"
        ? "animate-ring-pulse"
        : state === "celebrating"
          ? "animate-pop-in"
          : "animate-float-soft"

  return (
    <div
      className={cn("relative inline-flex items-center justify-center", className)}
      style={{ width: px, height: px }}
      role="img"
      aria-label={label ?? `Shampy, the AI employee, ${state}`}
    >
      <span
        className={cn("absolute inset-0 rounded-full", animationClass)}
        style={{ background: glow, opacity: 0.12 }}
        aria-hidden
      />
      <svg
        viewBox="0 0 120 120"
        width={px}
        height={px}
        className={cn("relative", animationEnabled && state !== "calling" ? "animate-float-soft" : "")}
        aria-hidden
      >
        <ellipse cx="60" cy="112" rx="26" ry="4" fill={INK} opacity={0.08} />

        <line x1="60" y1="30" x2="60" y2="19" stroke={BODY_DARK} strokeWidth={3.4} strokeLinecap="round" />
        <circle cx="60" cy="15" r="5.4" fill={state === "confused" ? CORAL : GREEN} />

        <rect x="18" y="52" width="9" height="18" rx="4.5" fill={BODY_DARK} />
        <rect x="93" y="52" width="9" height="18" rx="4.5" fill={BODY_DARK} />

        <rect x="24" y="30" width="72" height="66" rx="28" fill={BODY} />
        <rect x="24" y="30" width="72" height="66" rx="28" fill="url(#shampy-sheen)" opacity={0.35} />

        <rect x="36" y="42" width="48" height="34" rx="17" fill={FACE} />

        <Eyes state={state} />
        <Mouth state={state} />

        <circle cx="36" cy="68" r="3.6" fill={CORAL} opacity={0.28} />
        <circle cx="84" cy="68" r="3.6" fill={CORAL} opacity={0.28} />

        <rect x="46" y="98" width="12" height="9" rx="4" fill={BODY_DARK} />
        <rect x="62" y="98" width="12" height="9" rx="4" fill={BODY_DARK} />

        <Accessories state={state} />

        <defs>
          <linearGradient id="shampy-sheen" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="#FFFFFF" stopOpacity="0.55" />
            <stop offset="60%" stopColor="#FFFFFF" stopOpacity="0" />
          </linearGradient>
        </defs>
      </svg>
    </div>
  )
}
