import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { SiteHeader } from "@/components/site-header";
import { formatPrice, requireMember } from "@/lib/member";
import { Handoff } from "./handoff";

export default async function OfferPage({ params }: PageProps<"/offers/[id]">) {
  const { id } = await params;
  const { supabase, membership } = await requireMember();
  if (!/^[0-9a-f-]{36}$/i.test(id)) notFound();

  // RLS: only the buyer and seller get a row back; everyone else gets a 404.
  const { data: offer } = await supabase
    .from("offers")
    .select("id, thread_id, buyer_id, seller_id, state, amount_cents, expires_at, listings(title)")
    .eq("id", id)
    .maybeSingle();
  if (!offer) notFound();
  const role = offer.buyer_id === membership.user_id ? "buyer" : offer.seller_id === membership.user_id ? "seller" : null;
  if (!role) notFound();

  return (
    <>
      <SiteHeader email={membership.email} />
      <main className="mx-auto flex w-full max-w-md flex-1 flex-col px-4 py-4">
        <Link href={`/messages/${offer.thread_id}`} className="mb-4 inline-flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground">
          <ArrowLeft aria-hidden className="size-4" /> Back to the chat
        </Link>
        <p className="text-sm text-muted-foreground">{offer.listings?.title ?? "Your trade"}</p>
        <h1 className="mb-6 text-2xl font-semibold tracking-tight tabular-nums">
          {formatPrice(offer.amount_cents)} · {role === "buyer" ? "Your handoff code" : "Confirm the handoff"}
        </h1>
        <Handoff offerId={offer.id} threadId={offer.thread_id} role={role} initialState={offer.state}
          amount={offer.amount_cents} expiresAt={offer.expires_at} />
      </main>
    </>
  );
}
