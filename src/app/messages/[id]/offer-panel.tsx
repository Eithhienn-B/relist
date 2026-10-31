"use client";

import { useRef, useState, useTransition } from "react";
import Link from "next/link";
import { CircleCheck, Hourglass, Loader2, QrCode, ScanLine, ShieldCheck } from "lucide-react";
import { Button } from "@/components/ui/button";
import { formatPrice, parseDollars } from "@/lib/money";
import type { Tables } from "@/lib/supabase/database.types";
import { acceptOffer, cancelOffer, declineOffer, makeOffer, withdrawOffer } from "../offer-actions";

export type Offer = Pick<Tables<"offers">, "id" | "state" | "amount_cents" | "expires_at" | "created_at">;

const dayFmt = new Intl.DateTimeFormat("en-US", { weekday: "short", month: "short", day: "numeric", hour: "numeric", minute: "2-digit", timeZone: "America/Indiana/Indianapolis" });

// One panel above the composer that always says whose move it is and what it is.
export function OfferPanel({ threadId, isSeller, otherLabel, listingStatus, listingPrice, offers, onChange }: {
  threadId: string; isSeller: boolean; otherLabel: string; listingStatus: string | null; listingPrice: number | null;
  offers: Offer[]; onChange: () => void;
}) {
  const [pending, start] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [confirmCancel, setConfirmCancel] = useState(false);
  const section = useRef<HTMLElement>(null);
  const live = offers.find((o) => o.state === "pending" || o.state === "accepted");
  const done = offers.find((o) => o.state === "completed");
  const act = (fn: () => Promise<{ ok: true } | { ok: false; error: string }>) => start(async () => {
    setError(null);
    try {
      const res = await fn();
      if (!res.ok) setError(res.error);
    } catch {
      setError("Couldn't reach ReList. Check your connection and try again.");
    }
    setConfirmCancel(false);
    onChange();
    // The button that was pressed is gone; keep keyboard and screen-reader users in the panel.
    section.current?.focus();
  });

  let body: React.ReactNode = null;
  if (done) {
    body = (
      <Status icon={<CircleCheck className="text-brand" />} title={`Completed · sold for ${formatPrice(done.amount_cents)}`}>
        Handoff confirmed. {isSeller ? "The payment is on its way to you." : "Your card was charged just now, not before."}
      </Status>
    );
  } else if (live?.state === "accepted") {
    const by = live.expires_at ? dayFmt.format(new Date(live.expires_at)) : "";
    body = (
      <Status icon={<ShieldCheck className="text-brand" />} title={`Accepted at ${formatPrice(live.amount_cents)} · meet by ${by}`}>
        {isSeller
          ? "When you hand the item over, scan the buyer's code. That's when they're charged. No scan by then and the hold is released."
          : "Bring your phone to the meetup. Look the item over, then show the seller your code. You're only charged when they scan it."}
        <div className="mt-3 flex flex-wrap gap-2">
          <Button render={<Link href={`/offers/${live.id}`} />} className="press">
            {isSeller ? <><ScanLine aria-hidden /> Scan buyer&apos;s code</> : <><QrCode aria-hidden /> Show handoff code</>}
          </Button>
          {confirmCancel ? (
            <>
              <Button variant="destructive" disabled={pending} onClick={() => act(() => cancelOffer(live.id))} className="press">
                {pending ? <Loader2 aria-hidden className="animate-spin" /> : "Yes, cancel the trade"}
              </Button>
              <Button variant="ghost" onClick={() => setConfirmCancel(false)}>Keep it</Button>
            </>
          ) : (
            <Button variant="ghost" onClick={() => setConfirmCancel(true)}>Cancel trade</Button>
          )}
        </div>
      </Status>
    );
  } else if (live?.state === "pending") {
    body = isSeller ? (
      <Status icon={<Hourglass className="text-amber-600" />} title={`The ${otherLabel.toLowerCase()} offered ${formatPrice(live.amount_cents)}`}>
        Your move. Accepting holds the item for 4 days and turns down other offers. The buyer&apos;s card gets a hold, not a charge.
        <div className="mt-3 flex gap-2">
          <Button disabled={pending} onClick={() => act(() => acceptOffer(live.id))} className="press">
            {pending ? <Loader2 aria-hidden className="animate-spin" /> : "Accept"}
          </Button>
          <Button variant="outline" disabled={pending} onClick={() => act(() => declineOffer(live.id))} className="press">Decline</Button>
        </div>
      </Status>
    ) : (
      <Status icon={<Hourglass className="text-amber-600" />} title={`Your ${formatPrice(live.amount_cents)} offer is with the seller`}>
        Waiting on them. Nothing is charged until you meet up and they scan your code.
        <div className="mt-3">
          <Button variant="outline" disabled={pending} onClick={() => act(() => withdrawOffer(live.id))} className="press">Withdraw offer</Button>
        </div>
      </Status>
    );
  } else if (!isSeller && listingStatus === "active") {
    body = <MakeOffer threadId={threadId} price={listingPrice} onDone={() => { onChange(); section.current?.focus(); }} />;
  } else if (!isSeller && listingStatus && listingStatus !== "active") {
    body = (
      <Status icon={<Hourglass className="text-muted-foreground" />} title={listingStatus === "sold" ? "This item sold" : "On hold for another buyer"}>
        {listingStatus === "sold" ? "It went to someone else." : "If their trade falls through, it comes back and you can offer again."}
      </Status>
    );
  }
  if (!body) return null;
  return (
    <section ref={section} tabIndex={-1} aria-label="Offer" className="mb-2 rounded-xl border bg-card p-3 text-sm outline-none">
      {body}
      {error && <p role="alert" className="mt-2 text-xs text-destructive">{error}</p>}
    </section>
  );
}

function Status({ icon, title, children }: { icon: React.ReactNode; title: string; children: React.ReactNode }) {
  return (
    <div className="flex gap-2.5">
      <span aria-hidden className="mt-0.5 [&_svg]:size-4">{icon}</span>
      <div className="min-w-0 flex-1">
        <p aria-live="polite" className="font-medium tabular-nums">{title}</p>
        <div className="mt-0.5 text-muted-foreground">{children}</div>
      </div>
    </div>
  );
}

function MakeOffer({ threadId, price, onDone }: { threadId: string; price: number | null; onDone: () => void }) {
  const [amount, setAmount] = useState(price ? String(price / 100) : "");
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        const cents = parseDollars(amount);
        if (cents === null) { setError("Enter an amount like 25 or 25.50."); return; }
        start(async () => {
          try {
            const res = await makeOffer(threadId, cents);
            if (res.ok) { setError(null); onDone(); } else setError(res.error);
          } catch {
            setError("Couldn't reach ReList. Check your connection and try again.");
          }
        });
      }}
    >
      <label htmlFor="offer-amount" className="font-medium">Make an offer</label>
      <p id="offer-hint" className="mt-0.5 text-muted-foreground">
        If the seller accepts, you meet up and they scan your code. Your card is only charged at the handoff.
      </p>
      <div className="mt-2 flex gap-2">
        <div className="relative w-32">
          <span aria-hidden className="pointer-events-none absolute top-1/2 left-3 -translate-y-1/2 text-muted-foreground">$</span>
          <input id="offer-amount" inputMode="decimal" autoComplete="off" value={amount} aria-describedby="offer-hint"
            onChange={(e) => setAmount(e.target.value)}
            className="h-10 w-full rounded-lg border bg-transparent pr-3 pl-6 text-base tabular-nums outline-none focus-visible:ring-2 focus-visible:ring-ring md:text-sm" />
        </div>
        <Button type="submit" disabled={pending || !amount.trim()} className="press h-10">
          {pending ? <Loader2 aria-hidden className="animate-spin" /> : "Send offer"}
        </Button>
      </div>
      {error && <p role="alert" className="mt-2 text-xs text-destructive">{error}</p>}
    </form>
  );
}
