"use client";

import { useCallback, useEffect, useRef, useState, useSyncExternalStore, useTransition } from "react";
import Link from "next/link";
import { Camera, CircleCheck, CircleX, Hourglass, Loader2, ShieldAlert, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { formatPrice } from "@/lib/money";
import { qrPath } from "@/lib/qr";
import { createClient } from "@/lib/supabase/client";
import { redeemCode } from "@/app/messages/offer-actions";

type Role = "buyer" | "seller";
const END_STATES: Record<string, { title: string; body: string }> = {
  cancelled: { title: "This trade was cancelled", body: "Nothing was charged. The hold on the buyer's card is released." },
  expired: { title: "This trade expired", body: "No handoff within 4 days, so nothing was charged and the hold is released." },
  declined: { title: "This offer was declined", body: "Nothing was charged." },
  withdrawn: { title: "This offer was withdrawn", body: "Nothing was charged." },
  pending: { title: "Waiting for the seller to accept", body: "The code appears here once they do." },
};
const dayFmt = new Intl.DateTimeFormat("en-US", { weekday: "short", month: "short", day: "numeric", hour: "numeric", minute: "2-digit", timeZone: "America/Indiana/Indianapolis" });

export function Handoff({ offerId, threadId, role, initialState, amount, expiresAt }: {
  offerId: string; threadId: string; role: Role; initialState: string; amount: number; expiresAt: string | null;
}) {
  const [state, setState] = useState(initialState);

  // The database is the truth: re-read the offer whenever something says it moved (or we might have missed it).
  const refresh = useCallback(async () => {
    const { data } = await createClient().from("offers").select("state").eq("id", offerId).maybeSingle();
    if (data) setState(data.state);
  }, [offerId]);

  // Both screens follow the offer live: the buyer's flips to Completed the moment the seller scans. A phone that
  // was locked during the scan catches up on resubscribe and when the tab comes back.
  useEffect(() => {
    const supabase = createClient();
    let channel: ReturnType<typeof supabase.channel> | undefined;
    let cancelled = false;
    void supabase.realtime.setAuth().then(() => {
      if (cancelled) return;
      channel = supabase.channel(`offer:${offerId}`)
        .on("postgres_changes", { event: "INSERT", schema: "public", table: "messages", filter: `thread_id=eq.${threadId}` },
          ({ new: m }) => { if (m.offer_id === offerId && m.event) void refresh(); })
        .subscribe((status) => { if (status === "SUBSCRIBED") void refresh(); });
    });
    const onVisible = () => { if (document.visibilityState === "visible") void refresh(); };
    document.addEventListener("visibilitychange", onVisible);
    return () => {
      cancelled = true;
      document.removeEventListener("visibilitychange", onVisible);
      if (channel) void supabase.removeChannel(channel);
    };
  }, [offerId, threadId, refresh]);

  const heading = useRef<HTMLParagraphElement>(null);
  useEffect(() => { if (state !== "accepted") heading.current?.focus(); }, [state]);

  if (state === "completed") {
    return (
      <div className="rounded-2xl bg-brand-soft p-6 text-center">
        <CircleCheck aria-hidden className="mx-auto mb-3 size-10 text-brand" />
        <p ref={heading} tabIndex={-1} className="text-xl font-semibold outline-none">Completed</p>
        <p className="mt-1 text-sm text-muted-foreground tabular-nums">
          Sold for {formatPrice(amount)}. {role === "buyer" ? "Your card is charged now, not before." : "The payment is on its way to you."}
        </p>
        <Button render={<Link href={`/messages/${threadId}`} />} variant="outline" className="press mt-5">Back to the chat</Button>
      </div>
    );
  }
  if (state !== "accepted") {
    const end = END_STATES[state] ?? { title: "This trade has ended", body: "Nothing was charged." };
    return (
      <div className="rounded-2xl border p-6 text-center">
        {state === "pending" ? <Hourglass aria-hidden className="mx-auto mb-3 size-8 text-muted-foreground" />
          : <CircleX aria-hidden className="mx-auto mb-3 size-8 text-muted-foreground" />}
        <p ref={heading} tabIndex={-1} className="font-semibold outline-none">{end.title}</p>
        <p className="mt-1 text-sm text-muted-foreground">{end.body}</p>
      </div>
    );
  }
  return role === "buyer"
    ? <BuyerCode offerId={offerId} expiresAt={expiresAt} onGone={refresh} />
    : <SellerRedeem offerId={offerId} amount={amount} onDone={refresh} />;
}

function BuyerCode({ offerId, expiresAt, onGone }: { offerId: string; expiresAt: string | null; onGone: () => void }) {
  const [code, setCode] = useState<string | null>(null);
  const [left, setLeft] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const deadline = useRef(0); // when to fetch the next code (local clock)
  const inflight = useRef(false);

  const load = useCallback(async () => {
    if (inflight.current) return;
    inflight.current = true;
    const sent = Date.now();
    try {
      const { data, error: err } = await createClient().rpc("handoff_code", { p_offer: offerId });
      const row = data?.[0];
      if (err || !row) {
        if (err?.code === "22023" || err?.code === "P0002") { onGone(); return; } // completed, cancelled or expired: re-read the offer
        throw err;
      }
      setError(null);
      setCode(row.code);
      // Count the countdown from when we asked, and roll over a second early, so a stale code is never on screen.
      deadline.current = sent + (row.seconds_left - 1) * 1000;
      setLeft(Math.max(0, row.seconds_left - 1));
    } catch {
      setCode(null);
      setError("Couldn't load your code. Check your connection.");
      deadline.current = Date.now() + 3000; // back off
    } finally {
      inflight.current = false;
    }
  }, [offerId, onGone]);

  useEffect(() => {
    // deadline starts at 0, so the first tick loads the code.
    const tick = setInterval(() => {
      const s = Math.ceil((deadline.current - Date.now()) / 1000);
      setLeft(Math.max(0, s));
      if (s <= 0) void load();
    }, 250);
    // Keep the screen awake while the code is up (re-requested when the tab comes back; the browser drops it on hide).
    let lock: { release: () => Promise<void> } | undefined;
    let gone = false;
    const wake = () => {
      void navigator.wakeLock?.request("screen")
        .then((l) => { if (gone) void l.release(); else lock = l; })
        .catch(() => {});
    };
    const onVisible = () => { if (document.visibilityState === "visible") wake(); };
    wake();
    document.addEventListener("visibilitychange", onVisible);
    return () => {
      gone = true;
      clearInterval(tick);
      document.removeEventListener("visibilitychange", onVisible);
      void lock?.release();
    };
  }, [load]);

  const qr = code ? qrPath(code) : null;
  return (
    <div className="flex flex-col items-center">
      <div className="rounded-2xl border bg-white p-3 shadow-sm">
        {qr ? (
          <svg role="img" aria-label="Handoff QR code" viewBox={`0 0 ${qr.size} ${qr.size}`} className="size-60" shapeRendering="crispEdges">
            <path d={qr.d} fill="#111" />
          </svg>
        ) : <div className="size-60 animate-pulse rounded-lg bg-muted" />}
      </div>
      {/* Not a live region: a screen reader shouldn't read the code aloud every 30 s in a crowded room. */}
      <p data-testid="handoff-digits" className="mt-4 font-mono text-4xl font-semibold tracking-[0.2em] tabular-nums">
        {code ? <><span className="sr-only">Code </span>{code.slice(0, 3)}&thinsp;{code.slice(3)}</> : "··· ···"}
      </p>
      {code && (
        <>
          <div className="mt-3 h-1 w-40 overflow-hidden rounded-full bg-muted" aria-hidden>
            <div className="h-full origin-left rounded-full bg-brand transition-transform duration-300 ease-linear"
              style={{ transform: `scaleX(${left / 30})` }} />
          </div>
          <p className="mt-1.5 text-xs text-muted-foreground tabular-nums">New code in {left}s</p>
        </>
      )}
      {error && <p role="alert" className="mt-2 text-xs text-destructive">{error}</p>}

      <ol className="mt-6 w-full space-y-2 text-sm">
        <li className="flex gap-2"><Step n={1} /> Meet somewhere public on campus and look the item over.</li>
        <li className="flex gap-2"><Step n={2} /> Happy with it? Let the seller scan this screen.</li>
        <li className="flex gap-2"><Step n={3} /> That&apos;s the moment you&apos;re charged. Not before.</li>
      </ol>
      <div role="note" className="mt-5 flex w-full gap-2 rounded-lg border border-amber-500/40 bg-amber-500/10 p-3 text-sm">
        <ShieldAlert aria-hidden className="mt-0.5 size-4 shrink-0 text-amber-600" />
        <p><span className="font-medium">Only show this in person.</span> Never text, send or read this code to anyone. A seller who asks for it before meeting is running a scam.</p>
      </div>
      {expiresAt && <p className="mt-4 text-xs text-muted-foreground">No scan by {dayFmt.format(new Date(expiresAt))} and the hold is released.</p>}
    </div>
  );
}

const Step = ({ n }: { n: number }) => (
  <span aria-hidden className="flex size-5 shrink-0 items-center justify-center rounded-full bg-brand-soft text-xs font-medium text-brand">{n}</span>
);

const noop = () => () => {};
const hasDetector = () => "BarcodeDetector" in window && !!navigator.mediaDevices?.getUserMedia;
type Detector = { detect: (src: HTMLVideoElement) => Promise<{ rawValue: string }[]> };

function SellerRedeem({ offerId, amount, onDone }: { offerId: string; amount: number; onDone: () => void }) {
  const [code, setCode] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const [scanning, setScanning] = useState(false);
  const canScan = useSyncExternalStore(noop, hasDetector, () => false);
  const video = useRef<HTMLVideoElement>(null);
  const scanButton = useRef<HTMLButtonElement>(null);
  const busy = useRef(false);

  const submit = useCallback((value: string) => {
    if (busy.current) return; // Enter, the button and a scan can all fire; send once
    busy.current = true;
    setError(null);
    start(async () => {
      try {
        const res = await redeemCode(offerId, value);
        if (res.ok) onDone(); else setError(res.error);
      } catch {
        // The server may have committed before the connection dropped: re-read the offer instead of guessing.
        setError("Couldn't reach ReList. Checking whether it went through…");
        onDone();
      } finally {
        busy.current = false;
      }
    });
  }, [offerId, onDone]);

  // Camera scan where the browser has BarcodeDetector (Chrome/Android); typed code everywhere else.
  useEffect(() => {
    if (!scanning) return;
    let stream: MediaStream | undefined;
    let stop = false;
    (async () => {
      try {
        const s = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "environment" } });
        stream = s;
        if (stop || !video.current) { s.getTracks().forEach((t) => t.stop()); return; }
        video.current.srcObject = s;
        await video.current.play();
        const Ctor = (window as unknown as { BarcodeDetector: new (o: { formats: string[] }) => Detector }).BarcodeDetector;
        const detector = new Ctor({ formats: ["qr_code"] });
        while (!stop) {
          const found = (await detector.detect(video.current).catch(() => []))[0]?.rawValue;
          if (found && /^\d{6}$/.test(found)) { setScanning(false); setCode(found); submit(found); break; }
          await new Promise((r) => setTimeout(r, 300));
        }
      } catch (err) {
        if (stop) return;
        setError(err instanceof DOMException && err.name === "NotAllowedError"
          ? "Camera access is off for this site. Type the 6 digits instead, or allow the camera in your browser settings."
          : "Couldn't open the camera. Type the 6 digits instead.");
        setScanning(false);
      }
    })();
    return () => { stop = true; stream?.getTracks().forEach((t) => t.stop()); };
  }, [scanning, submit]);

  const stopScan = () => { setScanning(false); requestAnimationFrame(() => scanButton.current?.focus()); };

  return (
    <div>
      <p className="text-sm text-muted-foreground">
        Check the item over with the buyer first. Scanning their code confirms the handoff and charges them {formatPrice(amount)}.
      </p>
      {canScan && (
        <div className="mt-4">
          {scanning ? (
            <div className="relative overflow-hidden rounded-2xl bg-black">
              <video ref={video} muted playsInline className="aspect-square w-full object-cover" aria-label="Camera view" />
              <p role="status" className="absolute inset-x-0 bottom-0 bg-black/60 p-2 text-center text-sm text-white">Point at the buyer&apos;s QR code</p>
              <Button autoFocus variant="secondary" size="icon" aria-label="Stop scanning" onClick={stopScan} className="press absolute top-2 right-2">
                <X aria-hidden />
              </Button>
            </div>
          ) : (
            <Button ref={scanButton} size="lg" className="press w-full" onClick={() => { setError(null); setScanning(true); }}>
              <Camera aria-hidden /> Scan the buyer&apos;s code
            </Button>
          )}
        </div>
      )}
      <form className="mt-4" onSubmit={(e) => { e.preventDefault(); if (!pending) submit(code); }}>
        <label htmlFor="handoff-code" className="text-sm font-medium">{canScan ? "Or type the 6 digits" : "Type the 6 digits on the buyer's screen"}</label>
        <div className="mt-1.5 flex gap-2">
          <input id="handoff-code" inputMode="numeric" autoComplete="off" maxLength={7} value={code}
            onChange={(e) => setCode(e.target.value.replace(/[^\d ]/g, ""))}
            className="h-11 w-full rounded-lg border bg-transparent px-3 text-center font-mono text-xl tracking-[0.3em] tabular-nums outline-none focus-visible:ring-2 focus-visible:ring-ring" />
          <Button type="submit" disabled={pending || code.replace(/\D/g, "").length !== 6} className="press h-11">
            {pending ? <Loader2 aria-hidden className="animate-spin" /> : "Confirm"}
          </Button>
        </div>
        {error && <p role="alert" className="mt-2 text-sm text-destructive">{error}</p>}
      </form>
      <p className="mt-6 text-xs text-muted-foreground">
        The buyer&apos;s code changes every 30 seconds and only works in person. If anyone sends you a code by message, don&apos;t trust it.
      </p>
    </div>
  );
}
