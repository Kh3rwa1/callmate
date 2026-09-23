import * as React from "react"
import { CalendarCheck, MessageCircle, Pencil, PhoneCall, Clock, Wallet } from "lucide-react"

import { ROUTES } from "@/app/routes"
import { useRouter } from "@/app/router"
import { useApp } from "@/core/state/AppStoreProvider"
import { AppScaffold, SectionHeader } from "@/core/widgets/AppScaffold"
import { AvatarImage } from "@/core/widgets/MetricCard"
import { CustomerStatusBadge } from "@/core/widgets/CustomerStatusBadge"
import { PrimaryButton, SecondaryButton } from "@/core/widgets/Buttons"
import { TimelineWidget } from "@/core/widgets/TimelineWidget"
import { EmptyState } from "@/core/widgets/EmptyState"
import { formatAppointment, formatElapsed } from "@/core/utils/date"
import { FOLLOW_UP_TYPE_META } from "@/data/models/followUp"
import { StatusPill, type Tone } from "@/core/widgets/StatusPill"
import { BackendError } from "@/data/backend/client"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"

export function CustomerDetailScreen({ contactId }: { contactId: string }) {
  const { state, dispatch, repositories } = useApp()
  const { navigate, back } = useRouter()
  const [editing, setEditing] = React.useState(false)
  const [saving, setSaving] = React.useState(false)

  const contact = state.data.contacts.find((item) => item.id === contactId)

  const [name, setName] = React.useState(contact?.name ?? "")
  const [phone, setPhone] = React.useState(contact?.phone ?? "")
  const [service, setService] = React.useState(contact?.service ?? "")
  const [notes, setNotes] = React.useState(contact?.notes ?? "")

  if (!contact) {
    return (
      <AppScaffold title="Customer" onBack={back}>
        <EmptyState
          mascotState="confused"
          title="We couldn't find this customer"
          description="They may have been removed. Let's head back to your pipeline."
          actionLabel="Back to pipeline"
          onAction={() => navigate(ROUTES.pipeline, { replace: true })}
        />
      </AppScaffold>
    )
  }

  const upcomingFollowUp = state.data.followUps.find(
    (item) => item.contactId === contact.id && item.status === "pending"
  )

  async function handleSave() {
    if (!contact) return
    setSaving(true)
    try {
      // Saved on the backend so the details Shampy uses when calling stay in sync.
      await repositories.contacts.updateContact(contact.id, {
        name: name.trim() || contact.name,
        phone: phone.trim() || contact.phone,
        service: service.trim() || contact.service,
        notes,
      })
      dispatch({ type: "setToast", message: `${name.trim() || contact.name} updated` })
      setEditing(false)
    } catch (error) {
      dispatch({
        type: "setToast",
        message: error instanceof BackendError ? error.message : "We couldn't save those changes.",
      })
    } finally {
      setSaving(false)
    }
  }

  return (
    <AppScaffold
      title="Customer"
      onBack={back}
      action={
        <button
          type="button"
          onClick={() => setEditing(true)}
          className="flex size-11 items-center justify-center rounded-full border border-border/70 bg-card shadow-card active:scale-95"
          aria-label="Edit customer"
        >
          <Pencil className="size-5 text-ink" aria-hidden />
        </button>
      }
    >
      <section className="flex flex-col items-center rounded-3xl border border-border/70 bg-card p-5 text-center shadow-card">
        <AvatarImage name={contact.name} color={contact.avatarColor} size="xl" />
        <h2 className="text-hero mt-3 text-ink">{contact.name}</h2>
        <p className="text-caption mt-0.5 text-ink-soft">{contact.phone}</p>
        <div className="mt-3">
          <CustomerStatusBadge status={contact.status} size="md" />
        </div>

        <div className="mt-4 flex w-full gap-2.5">
          <PrimaryButton
            tone="brand"
            icon={<PhoneCall />}
            onClick={() => navigate(ROUTES.startCalling)}
          >
            Call
          </PrimaryButton>
          <PrimaryButton
            tone="blue"
            icon={<MessageCircle />}
            onClick={() => navigate(ROUTES.whatsapp(contact.id))}
          >
            WhatsApp
          </PrimaryButton>
        </div>
      </section>

      {contact.appointment && (
        <section className="mt-4 overflow-hidden rounded-3xl border border-brand/20 bg-brand-soft p-5">
          <div className="flex items-center gap-2 text-[#0E8F56]">
            <CalendarCheck className="size-5" aria-hidden />
            <span className="text-caption font-bold tracking-wide uppercase">Appointment</span>
          </div>
          <p className="mt-2 text-[22px] leading-tight font-extrabold text-ink">
            {formatAppointment(contact.appointment.date, contact.appointment.time)}
          </p>
          <p className="text-caption mt-1 text-[#0E8F56]">{contact.appointment.service}</p>
        </section>
      )}

      <section className="mt-4 grid grid-cols-2 gap-2.5">
        <div className="rounded-3xl border border-border/70 bg-card p-4 shadow-card">
          <div className="flex items-center gap-1.5 text-ink-soft">
            <Clock className="size-4" aria-hidden />
            <span className="text-[12px] font-bold tracking-wide uppercase">Last call</span>
          </div>
          <p className="text-[15px] mt-1.5 font-bold text-ink">
            {contact.lastCallAt ? formatElapsed(contact.lastCallAt) : "Not called yet"}
          </p>
          {contact.lastCallOutcome && (
            <p className="text-caption mt-0.5 truncate text-ink-soft">{contact.lastCallOutcome}</p>
          )}
        </div>

        <div className="rounded-3xl border border-border/70 bg-card p-4 shadow-card">
          <div className="flex items-center gap-1.5 text-ink-soft">
            <Wallet className="size-4" aria-hidden />
            <span className="text-[12px] font-bold tracking-wide uppercase">Recovered</span>
          </div>
          <p className="text-[15px] mt-1.5 font-bold text-ink">
            {contact.recoveredAmount ? `\u20B9${contact.recoveredAmount.toLocaleString("en-IN")}` : "\u2014"}
          </p>
          <p className="text-caption mt-0.5 text-ink-soft">Payments collected</p>
        </div>
      </section>

      {upcomingFollowUp && (
        <section className="mt-4">
          <SectionHeader title="Next step" />
          <div className="flex items-center gap-3 rounded-3xl border border-border/70 bg-card p-4 shadow-card">
            <StatusPill tone={FOLLOW_UP_TYPE_META[upcomingFollowUp.type].tone as Tone} size="md">
              {FOLLOW_UP_TYPE_META[upcomingFollowUp.type].label}
            </StatusPill>
            <p className="text-caption flex-1 text-ink-soft">{upcomingFollowUp.message}</p>
          </div>
        </section>
      )}

      {contact.notes && (
        <section className="mt-4">
          <SectionHeader title="Notes" />
          <p className="text-body rounded-3xl border border-border/70 bg-card p-4 text-ink shadow-card">
            {contact.notes}
          </p>
        </section>
      )}

      <section className="mt-5">
        <SectionHeader title="Timeline" />
        <TimelineWidget entries={contact.timeline} />
      </section>

      <div className="mt-6">
        <SecondaryButton onClick={() => navigate(ROUTES.pipeline, { replace: true })}>
          Back to pipeline
        </SecondaryButton>
      </div>

      <Dialog open={editing} onOpenChange={setEditing}>
        <DialogContent className="max-w-[calc(100vw-2.5rem)] rounded-3xl sm:max-w-sm">
          <DialogHeader>
            <DialogTitle className="text-title">Edit customer</DialogTitle>
            <DialogDescription className="text-caption text-ink-soft">
              Keep the details Shampy uses when calling.
            </DialogDescription>
          </DialogHeader>

          <div className="flex flex-col gap-4">
            <div className="flex flex-col gap-2">
              <Label htmlFor="edit-name" className="text-caption font-bold text-ink">Name</Label>
              <Input id="edit-name" value={name} onChange={(e) => setName(e.target.value)} className="h-12 rounded-2xl" />
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="edit-phone" className="text-caption font-bold text-ink">Phone</Label>
              <Input id="edit-phone" value={phone} onChange={(e) => setPhone(e.target.value)} className="h-12 rounded-2xl" />
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="edit-service" className="text-caption font-bold text-ink">Service</Label>
              <Input id="edit-service" value={service} onChange={(e) => setService(e.target.value)} className="h-12 rounded-2xl" />
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="edit-notes" className="text-caption font-bold text-ink">Notes</Label>
              <Textarea id="edit-notes" value={notes} onChange={(e) => setNotes(e.target.value)} className="min-h-24 rounded-2xl" />
            </div>
            <PrimaryButton onClick={handleSave} loading={saving}>
              Save changes
            </PrimaryButton>
          </div>
        </DialogContent>
      </Dialog>
    </AppScaffold>
  )
}
