"use client";

import { useActionState, useState, useTransition } from "react";
import { Loader2, Lock, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { CATEGORIES } from "@/lib/categories";
import { removeListing, updateListing } from "./actions";

const fieldClass =
  "w-full rounded-md border border-input bg-transparent px-3 text-sm shadow-xs outline-none focus-visible:ring-[3px] focus-visible:ring-ring/50";

type Listing = { id: string; title: string; description: string; price_cents: number; category: string };

export function EditForm({ listing, priceLocked }: { listing: Listing; priceLocked: boolean }) {
  const [error, action, saving] = useActionState(updateListing.bind(null, listing.id), undefined);
  const [confirmRemove, setConfirmRemove] = useState(false);
  const [removeError, setRemoveError] = useState<string>();
  const [removing, startRemove] = useTransition();

  return (
    <div className="mt-6 grid gap-8">
      <form action={action} className="grid gap-5">
        <div className="grid gap-2">
          <Label htmlFor="title">Title</Label>
          <Input id="title" name="title" required minLength={3} maxLength={80} defaultValue={listing.title} />
        </div>
        <div className="grid grid-cols-2 gap-4">
          <div className="grid gap-2">
            <Label htmlFor="price">Price</Label>
            <Input id="price" name="price" inputMode="decimal" required defaultValue={(listing.price_cents / 100).toFixed(2)}
              readOnly={priceLocked} aria-describedby={priceLocked ? "price-locked" : undefined} />
            {priceLocked && (
              <p id="price-locked" className="flex gap-1 text-xs text-muted-foreground">
                <Lock aria-hidden className="mt-0.5 size-3 shrink-0" /> Locked while an offer is accepted.
              </p>
            )}
          </div>
          <div className="grid gap-2">
            <Label htmlFor="category">Category</Label>
            <select id="category" name="category" required defaultValue={listing.category} className={`${fieldClass} h-9 capitalize`}>
              {CATEGORIES.map((c) => <option key={c} value={c}>{c}</option>)}
            </select>
          </div>
        </div>
        <div className="grid gap-2">
          <Label htmlFor="description">Description <span className="font-normal text-muted-foreground">(optional)</span></Label>
          <textarea id="description" name="description" rows={5} maxLength={2000} defaultValue={listing.description}
            className={`${fieldClass} py-2`} />
        </div>
        {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
        <Button type="submit" disabled={saving} className="press">
          {saving ? <Loader2 aria-hidden className="animate-spin" /> : "Save changes"}
        </Button>
        <p className="text-xs text-muted-foreground">Edits go through the same safety check as new listings.</p>
      </form>

      <section aria-labelledby="remove-heading" className="rounded-xl border p-4">
        <h2 id="remove-heading" className="font-medium">Take it down</h2>
        <p className="mt-1 text-sm text-muted-foreground">
          {priceLocked
            ? "An offer is accepted. Cancel the trade in the chat first, then you can take the listing down."
            : "Buyers stop seeing it right away, and anyone with an open offer is told it's gone."}
        </p>
        {removeError && <p role="alert" className="mt-2 text-sm text-destructive">{removeError}</p>}
        {!priceLocked && (confirmRemove ? (
          <div className="mt-3 flex gap-2">
            <Button variant="destructive" disabled={removing} className="press"
              onClick={() => startRemove(async () => { setRemoveError(await removeListing(listing.id)); })}>
              {removing ? <Loader2 aria-hidden className="animate-spin" /> : "Yes, take it down"}
            </Button>
            <Button variant="ghost" autoFocus onClick={() => setConfirmRemove(false)}>Keep it up</Button>
          </div>
        ) : (
          <Button variant="outline" className="press mt-3" onClick={() => setConfirmRemove(true)}>
            <Trash2 aria-hidden /> Take down listing
          </Button>
        ))}
      </section>
    </div>
  );
}
