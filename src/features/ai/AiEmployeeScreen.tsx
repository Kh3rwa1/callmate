import * as React from "react"
import {
  BarChart3,
  CalendarClock,
  Globe,
  MessageCircle,
  PhoneOutgoing,
  Sparkles,
  Volume2,
} from "lucide-react"

import { ROUTES } from "@/app/routes"
import { useRouter } from "@/app/router"
import { useApp } from "@/core/state/AppStoreProvider"
import { AppScaffold, SectionHeader, Surface } from "@/core/widgets/AppScaffold"
import { SettingsSelect } from "@/core/widgets/SettingsSelect"
import { SwitchRow } from "@/core/widgets/SettingsRow"
import { MascotWidget } from "@/core/widgets/MascotWidget"
import { PrimaryButton, SecondaryButton } from "@/core/widgets/Buttons"
import { StatusPill } from "@/core/widgets/StatusPill"
import {
  AI_CALL_STYLES,
  AI_LANGUAGES,
  AI_VOICES,
  type AiEmployeeSettings,
} from "@/data/models/business"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { backend } from "@/data/backend/client"

export function AiEmployeeScreen() {
  const { state, dispatch } = useApp()
  const { back, navigate } = useRouter()
  const [testing, setTesting] = React.useState(false)

  const { aiEmployee } = state
  const settings = aiEmployee.settings

  /**
   * These settings are the customer-facing view of the backend's agent
   * configuration. No provider detail is shown or stored here — the backend maps
   * them onto the voice service when it places calls.
   */
  function patchSettings(patch: Partial<AiEmployeeSettings>) {
    dispatch({ type: "updateAiSettings", patch })

    const backendPatch: Record<string, unknown> = {}
    if (patch.voice !== undefined) backendPatch.voice = patch.voice
    if (patch.language !== undefined) backendPatch.language = patch.language
    if (patch.callStyle !== undefined) backendPatch.call_style = patch.callStyle
    if (patch.workingHoursStart !== undefined) backendPatch.working_hours_start = patch.workingHoursStart
    if (patch.workingHoursEnd !== undefined) backendPatch.working_hours_end = patch.workingHoursEnd
    if (patch.followUpAutomation !== undefined) backendPatch.follow_up_enabled = patch.followUpAutomation
    if (Object.keys(backendPatch).length === 0) return

    void backend.updateAgent(backendPatch).catch(() => {
      dispatch({ type: "setToast", message: "We couldn't save that setting. Please try again." })
    })
  }

  function runTestCall() {
    setTesting(true)
    dispatch({ type: "setToast", message: `${aiEmployee.name} is preparing a test call…` })
    window.setTimeout(() => {
      setTesting(false)
      dispatch({ type: "setToast", message: "Test call finished. Everything sounds good." })
    }, 2200)
  }

  return (
    <AppScaffold title="Your AI employee" onBack={back} contentClassName="pt-4">
      <section className="flex flex-col items-center rounded-3xl border border-purple/20 bg-gradient-to-br from-purple-soft via-card to-blue-soft p-6 text-center shadow-raised">
        <MascotWidget state="happy" size="lg" />
        <h2 className="text-hero mt-3 text-ink">{aiEmployee.name}</h2>
        <div className="mt-2 flex flex-wrap items-center justify-center gap-2">
          <StatusPill tone={aiEmployee.active ? "green" : "neutral"} size="md">
            {aiEmployee.active ? "Active" : "Paused"}
          </StatusPill>
          <StatusPill tone="purple" size="md">
            {settings.language}
          </StatusPill>
          <StatusPill tone="blue" size="md">
            {settings.voice}
          </StatusPill>
        </div>
        <p className="text-body mt-3 max-w-xs text-ink-soft">
          {aiEmployee.name} answers your calls, books customers and follows up — in your language,
          any time of day.
        </p>

        <div className="mt-4 w-full">
          <PrimaryButton
            tone="purple"
            icon={<PhoneOutgoing />}
            onClick={runTestCall}
            loading={testing}
          >
            Test call
          </PrimaryButton>
        </div>
      </section>

      <section className="mt-6">
        <SectionHeader title="How Shampy sounds" />
        <Surface className="flex flex-col gap-4">
          <SettingsSelect
            label="Voice"
            icon={<Volume2 className="size-4 text-purple" />}
            value={settings.voice}
            options={AI_VOICES}
            onChange={(value) => patchSettings({ voice: value as (typeof AI_VOICES)[number] })}
          />
          <SettingsSelect
            label="Language"
            icon={<Globe className="size-4 text-blue" />}
            value={settings.language}
            options={AI_LANGUAGES}
            onChange={(value) =>
              patchSettings({ language: value as (typeof AI_LANGUAGES)[number] })
            }
          />
          <SettingsSelect
            label="Call style"
            icon={<MessageCircle className="size-4 text-brand" />}
            value={settings.callStyle}
            options={AI_CALL_STYLES}
            onChange={(value) =>
              patchSettings({ callStyle: value as (typeof AI_CALL_STYLES)[number] })
            }
          />
        </Surface>
      </section>

      <section className="mt-6">
        <SectionHeader title="When Shampy works" />
        <Surface className="flex flex-col gap-4">
          <div className="grid grid-cols-2 gap-3">
            <div className="flex flex-col gap-2">
              <Label htmlFor="start-time" className="text-caption font-bold text-ink">
                Starts
              </Label>
              <Input
                id="start-time"
                type="time"
                value={settings.workingHoursStart}
                onChange={(event) => patchSettings({ workingHoursStart: event.target.value })}
                className="h-12 rounded-2xl text-[15px]"
              />
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="end-time" className="text-caption font-bold text-ink">
                Stops
              </Label>
              <Input
                id="end-time"
                type="time"
                value={settings.workingHoursEnd}
                onChange={(event) => patchSettings({ workingHoursEnd: event.target.value })}
                className="h-12 rounded-2xl text-[15px]"
              />
            </div>
          </div>
          <p className="text-caption text-ink-soft">
            Outside these hours {aiEmployee.name} takes a message and calls back the next morning.
          </p>
        </Surface>
      </section>

      <section className="mt-6">
        <SectionHeader title="Follow-ups" />
        <div className="flex flex-col gap-2.5">
          <SwitchRow
            icon={<CalendarClock />}
            tone="amber"
            label="Create follow-ups automatically"
            description="Adds a reminder after every call"
            checked={settings.followUpAutomation}
            onCheckedChange={(value) => patchSettings({ followUpAutomation: value })}
          />
          <SwitchRow
            icon={<MessageCircle />}
            tone="green"
            label="Draft WhatsApp messages"
            description="Prepares a message you can send"
            checked={settings.autoWhatsApp}
            onCheckedChange={(value) => patchSettings({ autoWhatsApp: value })}
          />
          <SwitchRow
            icon={<Sparkles />}
            tone="purple"
            label={`${aiEmployee.name} is ${aiEmployee.active ? "on" : "off"}`}
            description="Pause to stop all calling"
            checked={aiEmployee.active}
            onCheckedChange={(value) =>
              dispatch({ type: "updateAiEmployee", patch: { active: value } })
            }
          />
        </div>
      </section>

      <div className="mt-6">
        <SecondaryButton icon={<BarChart3 className="text-blue" />} onClick={() => navigate(ROUTES.usage)}>
          See call usage
        </SecondaryButton>
      </div>
    </AppScaffold>
  )
}
