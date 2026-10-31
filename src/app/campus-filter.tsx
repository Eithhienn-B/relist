"use client";

import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";
import { LocateFixed } from "lucide-react";
import { Button } from "@/components/ui/button";
import { getPosition, locationErrorMessage } from "@/lib/geolocation";
import { nearestCampus } from "./sell/actions";

const selectClass =
  "h-10 rounded-md border border-input bg-transparent px-3 text-sm shadow-xs outline-none focus-visible:ring-[3px] focus-visible:ring-ring/50";

export function CampusFilter({ options, value, q }: { options: { id: number; label: string }[]; value: string; q: string }) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string>();
  const go = (campus: string) => {
    const params = new URLSearchParams({ campus });
    if (q) params.set("q", q);
    startTransition(() => router.push(`/?${params}`));
  };

  // "Near me" picks your nearest campus. The location is used once and never stored.
  async function nearMe() {
    setError(undefined);
    try {
      const pos = await getPosition();
      const id = await nearestCampus(pos.coords.latitude, pos.coords.longitude);
      if (id) go(String(id));
    } catch (e) {
      setError(locationErrorMessage(e));
    }
  }

  return (
    <div className="flex flex-col gap-1">
      <div className="flex gap-2">
        <select aria-label="Campus" value={value} onChange={(e) => go(e.target.value)} className={selectClass} disabled={pending}>
          <option value="all">All campuses</option>
          {options.map((o) => <option key={o.id} value={o.id}>{o.label}</option>)}
        </select>
        <Button type="button" variant="outline" className="press h-10" onClick={nearMe} disabled={pending}>
          <LocateFixed aria-hidden /> Near me
        </Button>
      </div>
      {error && <p role="alert" className="text-xs text-destructive">{error}</p>}
    </div>
  );
}
