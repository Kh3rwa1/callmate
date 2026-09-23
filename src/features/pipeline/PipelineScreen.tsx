import * as React from "react"
import { Plus, UserPlus } from "lucide-react"

import { ROUTES } from "@/app/routes"
import { useRouter } from "@/app/router"
import { useApp } from "@/core/state/AppStoreProvider"
import { AppScaffold, SectionHeader } from "@/core/widgets/AppScaffold"
import { BottomNavBar } from "@/core/widgets/BottomNavBar"
import { PipelineStageSelector } from "@/core/widgets/PipelineStageSelector"
import { CustomerCard, CardActionButton } from "@/core/widgets/CustomerCard"
import { FloatingActionButton, PrimaryButton, SecondaryButton } from "@/core/widgets/Buttons"
import { EmptyState } from "@/core/widgets/EmptyState"
import { CONTACT_STATUS_META } from "@/data/models/contact"
import { CATEGORY_DEFAULT_SERVICE } from "@/data/services/contactFactory"
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
import { PhoneCall, MessageCircle } from "lucide-react"

export function PipelineScreen() {
  const { state, dispatch, derived, repositories } = useApp()
  const { navigate } = useRouter()
  const [adding, setAdding] = React.useState(false)
  const [name, setName] = React.useState("")
  const [phone, setPhone] = React.useState("")
  const [service, setService] = React.useState("")
  const [error, setError] = React.useState<string | null>(null)
  const [saving, setSaving] = React.useState(false)

  const stage = state.selectedStage
  const stageContacts = state.data.contacts.filter((contact) => contact.status === stage)
  const selectedMeta = CONTACT_STATUS_META[stage]

  function handleAdd() {
    if (!name.trim()) {
      setError("Please enter the customer name")
      return
    }
    if (phone.replace(/\D/g, "").length < 10) {
      setError("Please enter a valid phone number")
      return
    }
    if (saving) return
    void save()
  }

  async function save() {
    setSaving(true)
    setError(null)
    try {
      // The backend stores the customer, so they survive a reload and are
      // available to the calling round.
      const contact = await repositories.contacts.createContact({
        name: name.trim(),
        phone: phone.trim(),
        service: service.trim() || CATEGORY_DEFAULT_SERVICE[state.business.category] || "Enquiry",
      })
      dispatch({ type: "setSelectedStage", stage: "new" })
      dispatch({ type: "setToast", message: `${contact.name} added to the pipeline` })
      setAdding(false)
      setName("")
      setPhone("")
      setService("")
    } catch (error) {
      setError(error instanceof BackendError ? error.message : "We couldn't add that customer.")
    } finally {
      setSaving(false)
    }
  }

  return (
    <AppScaffold
      title="Pipeline"
      subtitle={`${state.data.contacts.length} customers in total`}
      contentClassName="pt-3"
      footer={<BottomNavBar badges={{ followUps: derived.dashboardStats.followUpsDue, calls: derived.dashboardStats.callsActive }} />}
      floating={
        <FloatingActionButton
          label="Add customer"
          icon={<Plus />}
          onClick={() => setAdding(true)}
        />
      }
    >
      <PipelineStageSelector
        counts={derived.pipelineCounts}
        selected={stage}
        onSelect={(next) => dispatch({ type: "setSelectedStage", stage: next })}
      />

      <section className="mt-5">
        <SectionHeader
          title={`${selectedMeta.label} · ${stageContacts.length}`}
          action={
            <button
              type="button"
              onClick={() => setAdding(true)}
              className="text-caption min-tap inline-flex items-center gap-1 rounded-2xl px-2 font-bold text-brand"
            >
              <UserPlus className="size-4" aria-hidden />
              Add
            </button>
          }
        />

        {stageContacts.length === 0 ? (
          <EmptyState
            mascotState="confused"
            title={`No customers in ${selectedMeta.label.toLowerCase()}`}
            description="When Shampy moves a customer into this stage, they will appear here."
            actionLabel="Add your first customer"
            onAction={() => setAdding(true)}
          />
        ) : (
          <div className="flex flex-col gap-3">
            {stageContacts.map((contact) => (
              <CustomerCard
                key={contact.id}
                contact={contact}
                onClick={() => navigate(ROUTES.customer(contact.id))}
                action={
                  <>
                    <CardActionButton
                      label="Call"
                      tone="blue"
                      icon={<PhoneCall />}
                      onClick={(event) => {
                        event.stopPropagation()
                        navigate(ROUTES.startCalling)
                      }}
                    />
                    <CardActionButton
                      label="WhatsApp"
                      tone="green"
                      icon={<MessageCircle />}
                      onClick={(event) => {
                        event.stopPropagation()
                        navigate(ROUTES.whatsapp(contact.id))
                      }}
                    />
                  </>
                }
              />
            ))}
          </div>
        )}
      </section>

      <Dialog open={adding} onOpenChange={setAdding}>
        <DialogContent className="max-w-[calc(100vw-2.5rem)] rounded-3xl sm:max-w-sm">
          <DialogHeader>
            <DialogTitle className="text-title">Add customer</DialogTitle>
            <DialogDescription className="text-caption text-ink-soft">
              Shampy will call them and move them through the pipeline for you.
            </DialogDescription>
          </DialogHeader>

          <div className="flex flex-col gap-4">
            <div className="flex flex-col gap-2">
              <Label htmlFor="customer-name" className="text-caption font-bold text-ink">
                Name
              </Label>
              <Input
                id="customer-name"
                value={name}
                onChange={(event) => setName(event.target.value)}
                placeholder="Riya Das"
                className="h-12 rounded-2xl text-[15px]"
              />
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="customer-phone" className="text-caption font-bold text-ink">
                Phone
              </Label>
              <Input
                id="customer-phone"
                type="tel"
                inputMode="tel"
                value={phone}
                onChange={(event) => setPhone(event.target.value)}
                placeholder="+91 98301 22456"
                className="h-12 rounded-2xl text-[15px]"
              />
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="customer-service" className="text-caption font-bold text-ink">
                What do they need?
              </Label>
              <Input
                id="customer-service"
                value={service}
                onChange={(event) => setService(event.target.value)}
                placeholder="Dental consultation"
                className="h-12 rounded-2xl text-[15px]"
              />
            </div>

            {error && (
              <p className="text-caption rounded-2xl bg-coral-soft px-3.5 py-2.5 font-semibold text-[#C93B3B]" role="alert">
                {error}
              </p>
            )}

            <div className="flex flex-col gap-2.5">
              <PrimaryButton icon={<UserPlus />} onClick={handleAdd} loading={saving}>
                Add customer
              </PrimaryButton>
              <SecondaryButton onClick={() => setAdding(false)}>Cancel</SecondaryButton>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </AppScaffold>
  )
}
