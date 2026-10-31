"use client";

import { useState, useTransition } from "react";
import { Flag } from "lucide-react";
import { report } from "@/app/messages/actions";
import { Button } from "@/components/ui/button";
import { REPORT_REASONS } from "@/lib/report-reasons";

// "Report" link that opens an inline form. Used for messages and listings.
export function Report({ target, label = "Report" }: { target: { messageId: number } | { listingId: string }; label?: string }) {
  const [open, setOpen] = useState(false);
  const [done, setDone] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();

  if (done) return <span role="status" className="text-[11px] text-muted-foreground">Reported. Thanks for looking out.</span>;
  if (!open) {
    return (
      <button type="button" onClick={() => setOpen(true)} className={`-mx-1.5 inline-flex min-h-6 items-center gap-1 rounded px-1.5 text-[11px] text-muted-foreground hover:text-foreground`}>
        <Flag aria-hidden className="size-3" /> {label}
      </button>
    );
  }
  return (
    <form
      className="flex w-full max-w-sm flex-col gap-2 rounded-lg border bg-background p-3 text-sm"
      action={(fd) => start(async () => {
        const err = await report(target, String(fd.get("reason")), String(fd.get("note") ?? ""));
        if (err) setError(err); else setDone(true);
      })}
    >
      <label className="grid gap-1">
        <span className="text-xs font-medium">What&apos;s wrong?</span>
        <select name="reason" required defaultValue="" autoFocus className="h-9 rounded-md border bg-background px-2 text-base md:text-sm">
          <option value="" disabled>Pick a reason</option>
          {Object.entries(REPORT_REASONS).map(([value, text]) => <option key={value} value={value}>{text}</option>)}
        </select>
      </label>
      <label className="grid gap-1">
        <span className="text-xs font-medium">Anything else? (optional)</span>
        <textarea name="note" maxLength={500} rows={2} className="rounded-md border bg-transparent px-2 py-1 text-base md:text-sm" />
      </label>
      {error && <p role="alert" className="text-xs text-destructive">{error}</p>}
      <div className="flex justify-end gap-2">
        <Button type="button" size="sm" variant="ghost" onClick={() => setOpen(false)}>Cancel</Button>
        <Button type="submit" size="sm" disabled={pending} className="press">Send report</Button>
      </div>
    </form>
  );
}
