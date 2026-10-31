"use client";

import { useActionState, useEffect, useRef, useState, useTransition } from "react";
import { Check, ImagePlus, LocateFixed, MapPin, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { getPosition, locationErrorMessage } from "@/lib/geolocation";
import { MAX_PHOTOS } from "@/lib/photos-limits";
import { shrinkPhoto } from "@/lib/shrink-photo";
import { CATEGORIES } from "@/lib/categories";
import { checkLocation, createListing, type LocationResult } from "./actions";

const fieldClass =
  "w-full rounded-md border border-input bg-transparent px-3 text-sm shadow-xs outline-none focus-visible:ring-[3px] focus-visible:ring-ring/50";


type Passed = Extract<LocationResult, { ok: true }>;

export function SellForm({ initialCheck, minPrice }: { initialCheck?: Passed; minPrice: number }) {
  const [check, setCheck] = useState<Passed | undefined>(initialCheck);
  const [checkError, setCheckError] = useState<string>();
  const [checking, setChecking] = useState(false);
  const [error, action, saving] = useActionState(createListing, undefined);
  const [, startTransition] = useTransition();
  // Each picked file keeps its preview URL; URLs are revoked on remove and on unmount.
  const [photos, setPhotos] = useState<{ file: File; url: string }[]>([]);
  const latest = useRef(photos);
  useEffect(() => {
    latest.current = photos;
  }, [photos]);
  useEffect(() => () => latest.current.forEach((p) => URL.revokeObjectURL(p.url)), []);

  async function runCheck() {
    setChecking(true);
    setCheckError(undefined);
    try {
      const pos = await getPosition();
      const result = await checkLocation(pos.coords.latitude, pos.coords.longitude, pos.coords.accuracy);
      if (result.ok) setCheck(result);
      else setCheckError(result.error);
    } catch (e) {
      setCheckError(locationErrorMessage(e));
    } finally {
      setChecking(false);
    }
  }

  // Submit by hand: a form action would reset every field when the server returns an error.
  // The file input is cleared after each pick, so the chosen photos are appended here.
  async function submit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const formData = new FormData(e.currentTarget);
    formData.delete("photos");
    // Resize in the browser first (a 4 MB phone photo becomes ~0.5 MB); the server still re-encodes everything.
    for (const p of photos) formData.append("photos", await shrinkPhoto(p.file));
    startTransition(() => action(formData));
  }

  if (!check) {
    return (
      <section className="mt-6 rounded-2xl border p-6">
        <div className="flex size-10 items-center justify-center rounded-full bg-brand-soft text-brand">
          <MapPin aria-hidden className="size-5" />
        </div>
        <h2 className="mt-4 font-medium">First, a quick location check</h2>
        <p className="mt-1 text-sm text-muted-foreground">
          You need to be within 5 miles of a campus. We only keep whether you passed and which campus,
          never your location. One check covers your listings for 24 hours.
        </p>
        {checkError && <p role="alert" className="mt-3 text-sm text-destructive">{checkError}</p>}
        <Button type="button" className="press mt-5" onClick={runCheck} disabled={checking}>
          <LocateFixed aria-hidden /> {checking ? "Checking…" : "Check my location"}
        </Button>
      </section>
    );
  }

  return (
    <form onSubmit={submit} className="mt-6 grid gap-5">
      <div className="flex gap-2 rounded-lg bg-brand-soft px-3 py-2 text-sm">
        <Check aria-hidden className="mt-0.5 size-4 shrink-0 text-brand" />
        <p>
          Listing at <span className="font-medium">{check.campus} · {check.school}</span>
          {/* Local time differs between server and browser; the browser's wins. */}
          <span className="block text-xs text-muted-foreground" suppressHydrationWarning>
            Location check good until {new Date(check.expiresAt).toLocaleString([], { weekday: "short", hour: "numeric", minute: "2-digit" })}
          </span>
        </p>
      </div>

      <fieldset className="grid gap-2">
        <legend className="mb-2 text-sm font-medium">Photos <span className="font-normal text-muted-foreground">(up to {MAX_PHOTOS})</span></legend>
        <div className="grid grid-cols-4 gap-2">
          {photos.map(({ url: src }, i) => (
            <div key={src} className="relative aspect-square overflow-hidden rounded-lg bg-muted">
              {/* eslint-disable-next-line @next/next/no-img-element -- local blob preview */}
              <img src={src} alt={`Photo ${i + 1}`} className="size-full object-cover" />
              <button type="button" aria-label={`Remove photo ${i + 1}`}
                onClick={() => {
                  URL.revokeObjectURL(src);
                  setPhotos((ps) => ps.filter((_, j) => j !== i));
                }}
                className="press absolute top-1 right-1 rounded-full bg-background/90 p-1 shadow-sm">
                <X aria-hidden className="size-3" />
              </button>
            </div>
          ))}
          {photos.length < MAX_PHOTOS && (
            <label className="press flex aspect-square cursor-pointer flex-col items-center justify-center gap-1 rounded-lg border border-dashed text-xs text-muted-foreground hover:bg-muted focus-within:ring-[3px] focus-within:ring-ring/50">
              <ImagePlus aria-hidden className="size-5" />
              Add
              <input type="file" accept="image/jpeg,image/png,image/webp" multiple className="sr-only" aria-label="Add photos"
                onChange={(e) => {
                  const room = MAX_PHOTOS - photos.length;
                  const picked = Array.from(e.target.files ?? []).slice(0, room);
                  setPhotos((ps) => [...ps, ...picked.map((file) => ({ file, url: URL.createObjectURL(file) }))]);
                  e.target.value = "";
                }} />
            </label>
          )}
        </div>
      </fieldset>

      <div className="grid gap-2">
        <Label htmlFor="title">Title</Label>
        <Input id="title" name="title" required minLength={3} maxLength={80} placeholder="IKEA desk, white, 47 in" />
      </div>

      <div className="grid grid-cols-2 gap-3">
        <div className="grid gap-2">
          <Label htmlFor="price">Price</Label>
          <div className="relative">
            <span aria-hidden className="pointer-events-none absolute top-1/2 left-3 -translate-y-1/2 text-sm text-muted-foreground">$</span>
            <Input id="price" name="price" type="number" inputMode="decimal" required min={minPrice} max={10000} step="0.01"
              placeholder="25" className="pl-6 tabular-nums" />
          </div>
        </div>
        <div className="grid gap-2">
          <Label htmlFor="category">Category</Label>
          <select id="category" name="category" required defaultValue="" className={`${fieldClass} h-9 capitalize`}>
            <option value="" disabled>Choose…</option>
            {CATEGORIES.map((c) => <option key={c} value={c} className="capitalize">{c}</option>)}
          </select>
        </div>
      </div>

      <div className="grid gap-2">
        <Label htmlFor="description">Description <span className="font-normal text-muted-foreground">(optional)</span></Label>
        <textarea id="description" name="description" rows={4} maxLength={2000}
          placeholder="Condition, size, pickup times…" className={`${fieldClass} py-2`} />
      </div>

      <p className="text-xs text-muted-foreground">
        No alcohol, vapes, drugs, weapons, cribs, car seats, helmets or other items that are often recalled.{" "}
        <a href="https://www.cpsc.gov/Recalls" target="_blank" rel="noreferrer" className="underline underline-offset-2">Check recalls</a>.
      </p>

      {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
      <Button type="submit" size="lg" className="press" disabled={saving || photos.length === 0}>
        {saving ? "Posting…" : photos.length === 0 ? "Add a photo to post" : "Post listing"}
      </Button>
    </form>
  );
}
