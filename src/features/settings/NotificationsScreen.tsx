import { Bell } from "lucide-react"

import { BRAND } from "@/core/constants/brand"
import { useRouter } from "@/app/router"
import { useApp } from "@/core/state/AppStoreProvider"
import { AppScaffold } from "@/core/widgets/AppScaffold"
import { SwitchRow } from "@/core/widgets/SettingsRow"
import { NOTIFICATION_LABELS, type NotificationChannel } from "@/data/models/account"

const CHANNELS = Object.keys(NOTIFICATION_LABELS) as NotificationChannel[]

const TONE: Record<NotificationChannel, "green" | "blue" | "purple" | "amber"> = {
  calls: "blue",
  bookings: "green",
  followUps: "amber",
  payments: "purple",
}

export function NotificationsScreen() {
  const { state, dispatch } = useApp()
  const { back } = useRouter()

  return (
    <AppScaffold title="Notifications" onBack={back} contentClassName="pt-4">
      <p className="text-body mb-4 text-ink-soft">
        Choose what {BRAND.employeeName} should tell you about. Everything important stays on.
      </p>
      <div className="flex flex-col gap-2.5">
        {CHANNELS.map((channel) => (
          <SwitchRow
            key={channel}
            icon={<Bell />}
            tone={TONE[channel]}
            label={NOTIFICATION_LABELS[channel].label}
            description={NOTIFICATION_LABELS[channel].description}
            checked={state.notifications[channel]}
            onCheckedChange={() => dispatch({ type: "toggleNotification", channel })}
          />
        ))}
      </div>
    </AppScaffold>
  )
}
