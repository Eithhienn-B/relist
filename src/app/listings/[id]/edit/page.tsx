import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { SiteHeader } from "@/components/site-header";
import { requireMember } from "@/lib/member";
import { EditForm } from "./edit-form";

export default async function EditListingPage({ params }: PageProps<"/listings/[id]/edit">) {
  const { id } = await params;
  const { supabase, membership } = await requireMember();
  if (!/^[0-9a-f-]{36}$/i.test(id)) notFound();
  const { data: listing } = await supabase
    .from("listings")
    .select("id, seller_id, title, description, price_cents, category, status")
    .eq("id", id)
    .maybeSingle();
  if (!listing || listing.seller_id !== membership.user_id || listing.status === "sold" || listing.status === "removed") notFound();

  return (
    <>
      <SiteHeader email={membership.email} />
      <main className="mx-auto w-full max-w-xl flex-1 px-4 py-8">
        <Link href={`/listings/${id}`} className="mb-4 inline-flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground">
          <ArrowLeft aria-hidden className="size-4" /> Back to the listing
        </Link>
        <h1 className="text-2xl font-semibold tracking-tight">Edit listing</h1>
        <EditForm listing={listing} priceLocked={listing.status === "pending"} />
      </main>
    </>
  );
}
