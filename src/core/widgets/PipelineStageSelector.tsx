import { cn } from "@/lib/utils"
import type { ContactStatus } from "@/data/models/contact"
import { CONTACT_STATUS_META } from "@/data/models/contact"
import type { PipelineCounts } from "@/data/services/stats"
import { StatusIcon } from "@/core/widgets/StatusIcon"

/** Stages shown in the pipeline selector, in customer-journey order. */
export const PIPELINE_STAGES: ContactStatus[] = [
  "new",
  "calling",
  "followUp",
  "booked",
  "recovered",
]

const ACTIVE_STYLES: Record<ContactStatus, string> = {
  new: "border-ink/15 bg-ink text-white",
  calling: "border-blue bg-blue text-white",
  followUp: "border-amber bg-amber text-[#7A4D00]",
  booked: "border-brand bg-brand text-white",
  recovered: "border-brand bg-brand text-white",
  noResponse: "border-coral bg-coral text-white",
  notInterested: "border-ink-soft/40 bg-secondary text-ink",
}

export function PipelineStageSelector({
  counts,
  selected,
  onSelect,
}: {
  counts: PipelineCounts
  selected: ContactStatus
  onSelect: (stage: ContactStatus) => void
}) {
  return (
    <div
      className="no-scrollbar -mx-5 flex gap-2.5 overflow-x-auto px-5 pb-1"
      role="tablist"
      aria-label="Pipeline stages"
    >
      {PIPELINE_STAGES.map((stage) => {
        const meta = CONTACT_STATUS_META[stage]
        const active = selected === stage
        return (
          <button
            key={stage}
            type="button"
            role="tab"
            aria-selected={active}
            onClick={() => onSelect(stage)}
            className={cn(
              "flex min-tap shrink-0 flex-col items-start gap-1 rounded-3xl border px-4 py-3 text-left transition-all active:scale-[0.98]",
              active
                ? cn(ACTIVE_STYLES[stage], "shadow-raised")
                : "border-border/70 bg-card text-ink"
            )}
          >
            <span
              className={cn(
                "flex items-center gap-1.5 text-[11px] font-bold tracking-wide uppercase",
                active ? "opacity-90" : "text-ink-soft"
              )}
            >
              <StatusIcon status={stage} className="size-3.5" />
              {meta.label}
            </span>
            <span className="text-2xl leading-none font-extrabold">{counts[stage]}</span>
          </button>
        )
      })}
    </div>
  )
}
