import {
  Home,
  LayoutGrid,
  MoreHorizontal,
  PhoneCall,
  AlarmClock,
} from "lucide-react"

import { cn } from "@/lib/utils"
import { PRIMARY_TABS, type RouteId } from "@/app/routes"
import { useRouter } from "@/app/router"

const ICONS: Record<RouteId, React.ComponentType<{ className?: string }>> = {
  home: Home,
  pipeline: LayoutGrid,
  calls: PhoneCall,
  followUps: AlarmClock,
  more: MoreHorizontal,
  welcome: Home,
  login: Home,
  onboardingBusiness: Home,
  customer: Home,
  liveCall: PhoneCall,
  callResult: Home,
  startCalling: PhoneCall,
  campaign: PhoneCall,
  whatsapp: Home,
  aiEmployee: MoreHorizontal,
  business: MoreHorizontal,
  phoneNumber: MoreHorizontal,
  notifications: MoreHorizontal,
  subscription: MoreHorizontal,
  usage: MoreHorizontal,
}

/** Badge counts are passed in so the bar never reads business state itself. */
export type BottomNavBadges = Partial<Record<RouteId, number>>

export function BottomNavBar({ badges }: { badges?: BottomNavBadges }) {
  const { pathname, navigate } = useRouter()

  return (
    <nav
      className="safe-bottom sticky bottom-0 z-30 border-t border-border/70 bg-card/95 backdrop-blur-md"
      aria-label="Main navigation"
    >
      <ul className="mx-auto flex w-full max-w-[560px] items-stretch justify-between px-2 pt-1.5 pb-1.5">
        {PRIMARY_TABS.map((tab) => {
          const Icon = ICONS[tab.id]
          const active = pathname === tab.path
          const badge = badges?.[tab.id] ?? 0

          return (
            <li key={tab.id} className="flex-1">
              <button
                type="button"
                onClick={() => navigate(tab.path)}
                aria-current={active ? "page" : undefined}
                className={cn(
                  "relative flex min-h-[52px] w-full flex-col items-center justify-center gap-1 rounded-2xl px-1 transition-colors",
                  active ? "text-brand" : "text-ink-soft"
                )}
              >
                <span className="relative">
                  <Icon className={cn("size-[22px]", active && "stroke-[2.6]")} />
                  {badge > 0 && (
                    <span className="absolute -top-1.5 -right-2.5 flex min-w-4 items-center justify-center rounded-full bg-coral px-1 text-[10px] font-bold text-white">
                      {badge > 9 ? "9+" : badge}
                    </span>
                  )}
                </span>
                <span className={cn("text-[11px] font-semibold", active && "font-bold")}>
                  {tab.label}
                </span>
                {active && (
                  <span className="absolute top-0 h-1 w-8 rounded-full bg-brand" aria-hidden />
                )}
              </button>
            </li>
          )
        })}
      </ul>
    </nav>
  )
}
