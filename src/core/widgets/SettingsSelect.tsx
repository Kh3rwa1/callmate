import { Label } from "@/components/ui/label"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"

/** Labelled dropdown used by the AI employee settings. */
export function SettingsSelect({
  label,
  icon,
  value,
  options,
  onChange,
}: {
  label: string
  icon?: React.ReactNode
  value: string
  options: readonly string[]
  onChange: (value: string) => void
}) {
  return (
    <div className="flex flex-col gap-2">
      <Label className="text-caption flex items-center gap-2 font-bold text-ink">
        {icon}
        {label}
      </Label>
      <Select value={value} onValueChange={onChange}>
        <SelectTrigger className="h-12 w-full rounded-2xl text-[15px]">
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          {options.map((option) => (
            <SelectItem key={option} value={option}>
              {option}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
    </div>
  )
}
