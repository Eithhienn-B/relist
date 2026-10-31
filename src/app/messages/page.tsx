import Link from "next/link";
import { MessageCircle } from "lucide-react";
import { SiteHeader } from "@/components/site-header";
import { buttonVariants } from "@/components/ui/button";
import { formatPrice, requireMember, timeAgo } from "@/lib/member";

export default async function MessagesPage() {
  const { supabase, membership } = await requireMember();
  const me = membership.user_id;

  const { data: threads, error } = await supabase
    .from("threads")
    .select("id, buyer_id, seller_id, created_at, last_message_at, closed_at, listings(title, price_cents)")
    .order("last_message_at", { ascending: false, nullsFirst: false })
    .limit(100);
  // shortcut: one query for recent messages, newest per thread picked here; a view or RPC when inboxes grow.
  const ids = (threads ?? []).map((t) => t.id);
  const { data: recent } = ids.length
    ? await supabase.from("messages").select("thread_id, body, sender_id, created_at, held")
        .in("thread_id", ids).order("created_at", { ascending: false }).limit(500)
    : { data: [] };
  const last = new Map<string, NonNullable<typeof recent>[number]>();
  for (const m of recent ?? []) if (!last.has(m.thread_id)) last.set(m.thread_id, m);

  // A seller only sees a thread once a visible message exists (send_message sets last_message_at, held ones don't).
  const visible = (threads ?? []).filter((t) => t.buyer_id === me || t.last_message_at);

  return (
    <>
      <SiteHeader email={membership.email} />
      <main className="mx-auto w-full max-w-2xl flex-1 px-4 py-6">
        <h1 className="mb-4 text-2xl font-semibold tracking-tight">Messages</h1>
        {error && <p role="alert" className="text-sm text-destructive">Couldn&apos;t load messages. Refresh to try again.</p>}
        {!error && visible.length === 0 && (
          <div className="rounded-2xl border border-dashed px-6 py-16 text-center">
            <MessageCircle aria-hidden className="mx-auto mb-3 size-8 text-muted-foreground" />
            <p className="text-lg font-medium">No conversations yet.</p>
            <p className="mt-1 text-sm text-muted-foreground">Find something you like and tap &ldquo;Message seller&rdquo;. Buyers who message you show up here too.</p>
            <Link href="/" className={buttonVariants({ variant: "outline", className: "press mt-5" })}>Browse listings</Link>
          </div>
        )}
        <ul className="divide-y rounded-xl border empty:hidden">
          {visible.map((t) => {
            const m = last.get(t.id);
            const role = t.seller_id === me ? "Buyer" : "Seller";
            return (
              <li key={t.id}>
                <Link href={`/messages/${t.id}`} className="flex items-center gap-3 px-4 py-3 hover:bg-muted/50">
                  <div className="min-w-0 flex-1">
                    <p className="flex items-baseline gap-2">
                      <span className="truncate font-medium">{t.listings?.title ?? "Listing no longer available"}</span>
                      {t.listings && <span className="shrink-0 text-sm tabular-nums text-muted-foreground">{formatPrice(t.listings.price_cents)}</span>}
                    </p>
                    <p className="truncate text-sm text-muted-foreground">
                      {m ? (
                        <><span className="font-medium">{m.sender_id === me ? "You" : role}:</span> {m.held ? "Held for review" : m.body}</>
                      ) : t.last_message_at ? `Chat with the ${role.toLowerCase()}` : "No messages yet"}
                    </p>
                  </div>
                  <span className="shrink-0 text-xs text-muted-foreground">
                    {t.closed_at ? "Ended" : timeAgo(m?.created_at ?? t.last_message_at ?? t.created_at)}
                  </span>
                </Link>
              </li>
            );
          })}
        </ul>
      </main>
    </>
  );
}
