"use client";

import { useActionState } from "react";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Label } from "@/components/ui/label";
import { createMembership } from "./actions";

const selectClass =
  "h-9 w-full rounded-md border border-input bg-transparent px-3 text-sm shadow-xs outline-none focus-visible:ring-[3px] focus-visible:ring-ring/50";

export function OnboardingForm({ years }: { years: number[] }) {
  const [error, action, pending] = useActionState(createMembership, undefined);
  return (
    <form action={action} className="grid gap-4">
      <fieldset className="grid gap-2">
        <legend className="mb-2 text-sm font-medium">Expected graduation</legend>
        <div className="grid grid-cols-2 gap-2">
          <select name="grad_season" aria-label="Term" defaultValue="spring" className={selectClass}>
            <option value="spring">Spring</option>
            <option value="summer">Summer</option>
            <option value="fall">Fall</option>
          </select>
          <select name="grad_year" aria-label="Year" defaultValue={years[3]} className={selectClass}>
            {years.map((y) => <option key={y} value={y}>{y}</option>)}
          </select>
        </div>
      </fieldset>
      <div className="flex items-start gap-3">
        <Checkbox id="is_18_plus" name="is_18_plus" required />
        <Label htmlFor="is_18_plus" className="leading-snug font-normal">
          I&apos;m 18 or older. ReList is for adult students only.
        </Label>
      </div>
      {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
      <Button type="submit" disabled={pending}>{pending ? "Saving…" : "Finish sign-up"}</Button>
    </form>
  );
}
