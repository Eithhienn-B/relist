import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { SiteHeader } from "@/components/site-header";
import { formatPrice, requireMember } from "@/lib/member";
import { Chat } from "./chat";

export default async function ThreadPage({ params }: PageProps<"/messages/[id]">) {
  const { id } = await params;
  const { supabase, membership } = await requireMember();
  if (!/^[0-9a-f-]{36}$/i.test(id)) notFound();

  const { data: thread } = await supabase
    .from("threads")
    .select("id, listing_id, buyer_id, seller_id, closed_at, listings(title, price_cents, status, listing_photos(path, position))")
    .eq("id", id)
    .maybeSingle();
  if (!thread) notFound();

  // shortcut: loads the last 200 messages with no "load older"; add paging when a thread gets that long.
  const [{ data: messages }, { data: blocks }, { data: offers }] = await Promise.all([
    supabase.from("messages").select("*").eq("thread_id", id).order("created_at", { ascending: false }).limit(200),
    supabase.from("blocks").select("blocker_id, blocked_id"),
    supabase.from("offers").select("id, state, amount_cents, expires_at, created_at").eq("thread_id", id).order("created_at", { ascending: false }),
  ]);

  const me = membership.user_id;
  const isSeller = thread.seller_id === me;
  const other = isSeller ? thread.buyer_id : thread.seller_id;
  const withOther = (blocks ?? []).filter((b) => b.blocker_id === other || b.blocked_id === other);
  const blockedByMe = withOther.some((b) => b.blocker_id === me);
  const listing = thread.listings; // null when RLS hides it (removed, or a block)
  const photo = listing?.listing_photos.toSorted((a, b) => a.position - b.position)[0];
  const { data: signed } = photo ? await supabase.storage.from("listing-photos").createSignedUrl(photo.path, 600) : { data: null };

  return (
    <>
      <SiteHeader email={membership.email} />
      <main className="mx-auto flex w-full max-w-2xl flex-1 flex-col px-4 py-4">
        <Link href="/messages" className="mb-3 inline-flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground">
          <ArrowLeft aria-hidden className="size-4" /> Messages
        </Link>
        <div className="mb-3 flex items-center gap-3 rounded-xl border p-2 pr-3">
          {signed?.signedUrl ? (
            // eslint-disable-next-line @next/next/no-img-element -- short-lived signed URL
            <img src={signed.signedUrl} alt="" className="size-12 rounded-lg bg-muted object-cover" />
          ) : <div className="size-12 rounded-lg bg-muted" />}
          <div className="min-w-0 flex-1">
            {listing ? (
              <Link href={`/listings/${thread.listing_id}`} className="block truncate font-medium hover:underline">{listing.title}</Link>
            ) : <p className="truncate font-medium text-muted-foreground">Listing no longer available</p>}
            <p className="text-sm text-muted-foreground">
              {listing && <span className="tabular-nums">{formatPrice(listing.price_cents)} · </span>}
              {listing && listing.status !== "active" && <span className="font-medium text-foreground">{listing.status === "sold" ? "Sold" : "On hold"} · </span>}
              {isSeller ? "Chat with a buyer" : "Chat with the seller"}
            </p>
          </div>
        </div>
        <Chat
          threadId={thread.id}
          listingId={thread.listing_id}
          isSeller={isSeller}
          initialOffers={offers ?? []}
          initialListingStatus={listing?.status ?? null}
          listingPrice={listing?.price_cents ?? null}
          me={me}
          otherId={other}
          otherLabel={isSeller ? "Buyer" : "Seller"}
          initial={(messages ?? []).toReversed()}
          ended={Boolean(thread.closed_at) || withOther.length > 0}
          blockedByMe={blockedByMe}
        />
      </main>
    </>
  );
}
