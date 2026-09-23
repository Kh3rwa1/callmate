import * as React from "react"
import { MessageCircle, PhoneCall } from "lucide-react"

import { BRAND } from "@/core/constants/brand"
import { ROUTES } from "@/app/routes"
import { useRouter } from "@/app/router"
import { useApp } from "@/core/state/AppStoreProvider"
import { AppScaffold, SectionHeader } from "@/core/widgets/AppScaffold"
import { EmptyState } from "@/core/widgets/EmptyState"
import { PrimaryButton, SecondaryButton } from "@/core/widgets/Buttons"
import { AvatarImage } from "@/core/widgets/MetricCard"
import { WhatsAppMessageCard } from "@/core/widgets/WhatsAppMessageCard"
import { CustomerStatusBadge } from "@/core/widgets/CustomerStatusBadge"
import { generateMessages, pickMessage } from "@/data/services/whatsappService"
import { formatElapsed } from "@/core/utils/date"

export function WhatsAppScreen({ contactId }: { contactId: string }) {
  const { state, whatsapp, dispatch } = useApp()
  const { navigate, back } = useRouter()

  const contact = state.data.contacts.find((item) => item.id === contactId)
  const lastCall =
    state.data.calls
      .filter((call) => call.contactId === contactId)
      .sort((a, b) => b.startedAt.localeCompare(a.startedAt))[0] ?? null

  const drafts = React.useMemo(
    () =>
      contact
        ? generateMessages({
            contact,
            business: state.business,
            lastCall,
          })
        : [],
    [contact, state.business, lastCall]
  )

  const [variant, setVariant] = React.useState(0)
  const [editing, setEditing] = React.useState(false)
  const [customBody, setCustomBody] = React.useState<string | null>(null)
  const [sending, setSending] = React.useState(false)

  // A fresh contact (for example after a call outcome change) resets the draft.
  React.useEffect(() => {
    setVariant(0)
    setCustomBody(null)
    setEditing(false)
  }, [contactId, contact?.status])

  if (!contact) {
    return (
      <AppScaffold title="WhatsApp" onBack={back}>
        <EmptyState
          mascotState="confused"
          title="We couldn't find this customer"
          description="They may have been removed from your list."
          actionLabel="Back to follow-ups"
          onAction={() => navigate(ROUTES.followUps, { replace: true })}
        />
      </AppScaffold>
    )
  }

  // Captured after the guard so the closures below keep the narrowed type.
  const customer = contact
  const message = customBody ?? pickMessage(drafts, variant)

  function regenerate() {
    setCustomBody(null)
    setVariant((current) => (current + 1) % Math.max(1, drafts.length))
    dispatch({ type: "setToast", message: `${BRAND.employeeName} wrote a new message` })
  }

  function handleSend() {
    setSending(true)
    const opened = whatsapp.openWhatsApp(customer.phone, message)
    window.setTimeout(() => {
      setSending(false)
      if (opened) {
        dispatch({ type: "setToast", message: `WhatsApp opened for ${customer.name}` })
      } else {
        dispatch({
          type: "setToast",
          message: "Your browser blocked WhatsApp. Please allow pop-ups and try again.",
        })
      }
    }, 500)
  }

  return (
    <AppScaffold title="WhatsApp" onBack={back} contentClassName="pt-4">
      <section className="flex items-center gap-4 rounded-3xl border border-border/70 bg-card p-4 shadow-card">
        <AvatarImage name={contact.name} color={contact.avatarColor} size="lg" />
        <div className="min-w-0 flex-1">
          <p className="text-[17px] font-bold text-ink">{contact.name}</p>
          <p className="text-caption text-ink-soft">{contact.phone}</p>
          <div className="mt-2 flex flex-wrap items-center gap-2">
            <CustomerStatusBadge status={contact.status} />
            {contact.lastCallAt && (
              <span className="text-caption text-ink-soft">
                Last call {formatElapsed(contact.lastCallAt)}
              </span>
            )}
          </div>
        </div>
      </section>

      <section className="mt-5">
        <SectionHeader title="Message" />
        <WhatsAppMessageCard
          message={message}
          customerName={contact.name}
          editing={editing}
          sending={sending}
          onChange={(value) => setCustomBody(value)}
          onRegenerate={regenerate}
          onSend={handleSend}
          onToggleEdit={() => setEditing((value) => !value)}
        />
      </section>

      <div className="mt-5 flex flex-col gap-2.5">
        <PrimaryButton
          tone="blue"
          icon={<PhoneCall />}
          onClick={() => navigate(ROUTES.startCalling)}
        >
          Call instead
        </PrimaryButton>
        <SecondaryButton
          icon={<MessageCircle />}
          onClick={() => navigate(ROUTES.customer(contact.id))}
        >
          View customer
        </SecondaryButton>
      </div>

      <p className="text-caption mt-5 pb-2 text-center text-ink-soft">
        Sending opens WhatsApp with this message ready. You stay in control of the final send.
      </p>
    </AppScaffold>
  )
}
