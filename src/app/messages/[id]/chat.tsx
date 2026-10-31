"use client";

import { useCallback, useEffect, useMemo, useRef, useState, useTransition } from "react";
import { Ban, CircleCheck, CircleX, HandCoins, Hourglass, Loader2, SendHorizontal, ShieldAlert, ShieldCheck, Undo2 } from "lucide-react";
import { Report } from "@/components/report-form";
import { Button } from "@/components/ui/button";
import { detectOffPlatform, type OffPlatformKind } from "@/lib/nudge";
import { createClient } from "@/lib/supabase/client";
import { blockUser, sendMessage, type Message } from "../actions";
import { OfferPanel, type Offer } from "./offer-panel";

// key stays the same when an optimistic row is swapped for the saved one, so it isn't remounted or re-announced.
type Row = Message & { key: string; pending?: boolean };
const toRow = (m: Message): Row => ({ ...m, key: String(m.id) });
const merge = (prev: Row[], incoming: Message[]) => {
  const seen = new Set(prev.map((r) => r.id));
  const add = incoming.filter((m) => !seen.has(m.id)).map(toRow);
  return add.length ? [...prev, ...add] : prev;
};

// shortcut: the pilot is one campus timezone, so server and browser render the same clock; use the viewer's zone when campuses span zones.
const timeFmt = new Intl.DateTimeFormat("en-US", { hour: "numeric", minute: "2-digit", timeZone: "America/Indiana/Indianapolis" });
const ENDED = "This conversation has ended.";

function nudgeCopy(kinds: OffPlatformKind[]) {
  if (kinds.includes("payment")) {
    return "Payments stay in ReList, not Venmo, Zelle or cash. That's what protects your money until you meet up.";
  }
  return "Keep the chat here, so report and block still work if something feels off.";
}

export function Chat({ threadId, listingId, me, otherId, otherLabel, initial, ended, blockedByMe, isSeller, initialOffers, initialListingStatus, listingPrice }: {
  threadId: string; listingId: string; me: string; otherId: string; otherLabel: string;
  initial: Message[]; ended: boolean; blockedByMe: boolean;
  isSeller: boolean; initialOffers: Offer[]; initialListingStatus: string | null; listingPrice: number | null;
}) {
  const [rows, setRows] = useState<Row[]>(() => initial.map(toRow));
  const [offers, setOffers] = useState(initialOffers);
  const [listingStatus, setListingStatus] = useState(initialListingStatus);
  const [draft, setDraft] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [isEnded, setEnded] = useState(ended);
  const [confirmBlock, setConfirmBlock] = useState(false);
  const [blocking, startBlock] = useTransition();
  const bottom = useRef<HTMLDivElement>(null);
  const blockButton = useRef<HTMLButtonElement>(null);
  const tempId = useRef(-1);
  const lastId = useRef(Math.max(0, ...initial.map((m) => m.id)));

  // Offer state and listing status, re-read whenever an offer event lands (from either side or the expiry job).
  // Only the newest request may write state, so a slow older response can't roll the panel back.
  const offersSeq = useRef(0);
  const refreshOffers = useCallback(async () => {
    const seq = ++offersSeq.current;
    const supabase = createClient();
    const [{ data: o, error: oErr }, { data: l, error: lErr }] = await Promise.all([
      supabase.from("offers").select("id, state, amount_cents, expires_at, created_at").eq("thread_id", threadId).order("created_at", { ascending: false }),
      supabase.from("listings").select("status").eq("id", listingId).maybeSingle(),
    ]);
    if (seq !== offersSeq.current || oErr || lErr) return;
    if (o) setOffers(o);
    setListingStatus(l?.status ?? null);
  }, [threadId, listingId]);

  // Rows newer than the last one we have: covers the gap before SUBSCRIBED and any reconnect or backgrounded tab.
  const catchUp = useCallback(async () => {
    const { data } = await createClient().from("messages").select("*")
      .eq("thread_id", threadId).gt("id", lastId.current).order("id");
    if (data?.length) setRows((prev) => merge(prev, data));
    // Always re-read offers: an event row with a lower id can commit after a higher one we already have.
    void refreshOffers();
  }, [threadId, refreshOffers]);

  useEffect(() => {
    for (const r of rows) if (r.id > lastId.current) lastId.current = r.id;
  }, [rows]);

  // Live inserts. RLS on messages decides what this subscriber receives (held rows and other threads never arrive).
  useEffect(() => {
    const supabase = createClient();
    let channel: ReturnType<typeof supabase.channel> | undefined;
    let cancelled = false;
    // Join with the user's JWT. Without this the first join can go out with only the publishable key (= anon),
    // which RLS rightly gives nothing ("invalid column for filter").
    void supabase.realtime.setAuth().then(() => {
      if (cancelled) return;
      channel = supabase
        .channel(`thread:${threadId}`)
        .on("postgres_changes", { event: "INSERT", schema: "public", table: "messages", filter: `thread_id=eq.${threadId}` },
          ({ new: msg }) => {
            setRows((prev) => merge(prev, [msg as Message]));
            if ((msg as Message).event) void refreshOffers(); // an offer moved: re-read its state and the listing's
          })
        .subscribe((status) => { if (status === "SUBSCRIBED") void catchUp(); });
    });
    const onVisible = () => { if (document.visibilityState === "visible") void catchUp(); };
    document.addEventListener("visibilitychange", onVisible);
    return () => {
      cancelled = true;
      document.removeEventListener("visibilitychange", onVisible);
      if (channel) void supabase.removeChannel(channel);
    };
  }, [threadId, catchUp, refreshOffers]);

  // Follow new messages only when the reader is already near the bottom (or just sent one).
  const follow = useRef(true);
  useEffect(() => {
    if (follow.current) bottom.current?.scrollIntoView({ block: "end" });
  }, [rows.length]);
  useEffect(() => {
    const onScroll = () => { follow.current = window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 160; };
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  const kinds = useMemo(() => detectOffPlatform(draft), [draft]);
  const theyNudged = rows.some((r) => r.sender_id !== me && r.nudge);

  async function send() {
    const body = draft.trim();
    if (!body || isEnded) return;
    const id = tempId.current--;
    const key = `temp${id}`;
    follow.current = true;
    setRows((prev) => [...prev, { id, key, thread_id: threadId, sender_id: me, body, held: false, nudge: false, event: null, offer_id: null, created_at: new Date().toISOString(), pending: true }]);
    setDraft("");
    setError(null);
    let res: Awaited<ReturnType<typeof sendMessage>>;
    try {
      res = await sendMessage(threadId, body);
    } catch {
      res = { ok: false, error: "Couldn't send. Check your connection and try again." };
      void catchUp(); // in case it was saved before the connection dropped
    }
    if (res.ok) {
      const saved = res.message;
      // The realtime echo may already have added the saved row; keep one.
      setRows((prev) => prev.some((r) => r.id === saved.id)
        ? prev.filter((r) => r.id !== id)
        : prev.map((r) => (r.id === id ? { ...saved, key } : r)));
    } else {
      setRows((prev) => prev.filter((r) => r.id !== id));
      setDraft((d) => d || body); // don't clobber a newer draft typed while this one was in flight
      setError(res.error);
      if (res.error === ENDED) setEnded(true);
    }
  }

  return (
    <div className="flex flex-1 flex-col">
      {theyNudged && (
        <div role="note" className="mb-3 flex gap-2 rounded-lg border border-amber-500/40 bg-amber-500/10 p-3 text-sm">
          <ShieldAlert aria-hidden className="mt-0.5 size-4 shrink-0 text-amber-600" />
          <p><span className="font-medium">Keep payments in ReList.</span> Being asked to pay by Venmo, Zelle, Cash App or cash is how most student-marketplace scams start. You can report the message.</p>
        </div>
      )}

      {rows.length === 0 && (
        <div className="rounded-xl bg-brand-soft p-4 text-sm">
          <p className="mb-2 flex items-center gap-2 font-medium"><ShieldCheck aria-hidden className="size-4 text-brand" /> Before you meet</p>
          <ul className="ml-6 list-disc space-y-1 text-muted-foreground">
            <li>Meet on campus, somewhere public, in daylight.</li>
            <li>Pay only through ReList. Never Venmo, Zelle, Cash App, gift cards or cash.</li>
            <li>Never share a code sent to your phone or email.</li>
            <li>Look the item over before you pay.</li>
          </ul>
        </div>
      )}
      <ol role="log" aria-label="Messages" className="flex flex-1 flex-col gap-2 py-2">
        {rows.map((r) => r.event
          ? <EventCard key={r.key} row={r} mine={r.sender_id === me} otherLabel={otherLabel} />
          : <Bubble key={r.key} row={r} mine={r.sender_id === me} otherLabel={otherLabel} />)}
      </ol>
      <div ref={bottom} />

      {!isEnded && (
        <OfferPanel threadId={threadId} isSeller={isSeller} otherLabel={otherLabel} listingStatus={listingStatus}
          listingPrice={listingPrice} offers={offers} onChange={() => { void refreshOffers(); void catchUp(); }} />
      )}
      {isEnded ? (
        <p role="status" className="mt-2 rounded-lg bg-muted p-3 text-center text-sm text-muted-foreground">
          {blockedByMe ? `You blocked this ${otherLabel.toLowerCase()}. ` : ""}{ENDED}
        </p>
      ) : (
        <form className="sticky bottom-0 mt-2 border-t bg-background pt-3 pb-2" onSubmit={(e) => { e.preventDefault(); void send(); }}>
          {kinds.length > 0 && (
            <p role="status" className="mb-2 flex gap-2 text-xs text-amber-700 dark:text-amber-400">
              <ShieldAlert aria-hidden className="size-3.5 shrink-0 translate-y-0.5" /> {nudgeCopy(kinds)}
            </p>
          )}
          {error && <p role="alert" className="mb-2 text-xs text-destructive">{error}</p>}
          <div className="flex items-end gap-2">
            <label htmlFor="message" className="sr-only">Message</label>
            <textarea
              id="message"
              value={draft}
              onChange={(e) => setDraft(e.target.value)}
              onKeyDown={(e) => {
                // Enter sends on a keyboard; Shift+Enter is a newline; never send mid-IME composition.
                if (e.key === "Enter" && !e.shiftKey && !e.nativeEvent.isComposing) { e.preventDefault(); void send(); }
              }}
              rows={1}
              maxLength={2000}
              enterKeyHint="send"
              placeholder={`Message the ${otherLabel.toLowerCase()}`}
              className="field-sizing-content max-h-40 min-h-10 flex-1 resize-none rounded-lg border bg-transparent px-3 py-2 text-base outline-none focus-visible:ring-2 focus-visible:ring-ring md:text-sm"
            />
            <Button type="submit" disabled={!draft.trim()} className="press h-10" aria-label={kinds.length ? "Send anyway" : "Send"}>
              {kinds.length ? "Send anyway" : <SendHorizontal aria-hidden />}
            </Button>
          </div>
          <div className="mt-2 flex justify-end">
            {confirmBlock ? (
              <div role="group" aria-labelledby="block-confirm" className="flex flex-wrap items-center justify-end gap-2 text-xs">
                <span id="block-confirm">
                  Block this {otherLabel.toLowerCase()}? Neither of you can message, and you won&apos;t see each other&apos;s listings.
                </span>
                <Button type="button" size="sm" variant="destructive" disabled={blocking} className="press"
                  onClick={() => startBlock(async () => {
                    const err = await blockUser(threadId, otherId);
                    if (err) setError(err); else setEnded(true);
                    setConfirmBlock(false);
                  })}>
                  {blocking ? <Loader2 aria-hidden className="animate-spin" /> : "Block"}
                </Button>
                <Button type="button" size="sm" variant="ghost" autoFocus
                  onClick={() => { setConfirmBlock(false); requestAnimationFrame(() => blockButton.current?.focus()); }}>
                  Cancel
                </Button>
              </div>
            ) : (
              <Button ref={blockButton} type="button" size="sm" variant="ghost" className="text-muted-foreground" onClick={() => setConfirmBlock(true)}>
                <Ban aria-hidden /> Block
              </Button>
            )}
          </div>
        </form>
      )}
    </div>
  );
}

function Bubble({ row, mine, otherLabel }: { row: Row; mine: boolean; otherLabel: string }) {
  return (
    <li className={`flex flex-col gap-1 ${mine ? "items-end" : "items-start"}`}>
      <div className={`max-w-[80%] rounded-2xl px-3 py-2 text-sm whitespace-pre-wrap break-words ${
        row.held ? "rounded-br-sm border border-dashed border-amber-500 bg-amber-500/10"
          : mine ? "rounded-br-sm bg-primary text-primary-foreground" : "rounded-bl-sm bg-muted"
      } ${row.pending ? "opacity-60" : ""}`}>
        <span className="sr-only">{mine ? "You" : otherLabel}: </span>{row.body}
      </div>
      <div className="flex flex-wrap items-center gap-2 px-1 text-[11px] text-muted-foreground">
        {row.held
          ? <span className="text-amber-700 dark:text-amber-400">Held for review. Only you can see this.</span>
          : <time dateTime={row.created_at}>{row.pending ? "Sending…" : timeFmt.format(new Date(row.created_at))}</time>}
        {!mine && !row.held && row.id > 0 && <Report target={{ messageId: row.id }} />}
      </div>
    </li>
  );
}

const EVENT_ICON: Record<string, React.ReactNode> = {
  offer: <HandCoins />, accepted: <ShieldCheck />, completed: <CircleCheck />,
  declined: <CircleX />, withdrawn: <Undo2 />, cancelled: <CircleX />, expired: <Hourglass />,
};

// Offer events sit in the timeline as quiet system lines; the panel below carries the actions.
function EventCard({ row, mine, otherLabel }: { row: Row; mine: boolean; otherLabel: string }) {
  const strong = row.event === "completed";
  return (
    <li className="my-1 flex justify-center">
      <div className={`flex max-w-[90%] items-center gap-2 rounded-full border px-3 py-1.5 text-xs ${
        strong ? "border-brand/30 bg-brand-soft text-foreground" : "bg-background text-muted-foreground"}`}>
        <span aria-hidden className={`[&_svg]:size-3.5 ${strong || row.event === "accepted" ? "text-brand" : ""}`}>{EVENT_ICON[row.event!]}</span>
        <span>
          <span className="sr-only">{row.sender_id ? (mine ? "You: " : `${otherLabel}: `) : "ReList: "}</span>
          <span className="font-medium text-foreground tabular-nums">{row.body}</span>
          {" · "}<time dateTime={row.created_at}>{timeFmt.format(new Date(row.created_at))}</time>
        </span>
      </div>
    </li>
  );
}
