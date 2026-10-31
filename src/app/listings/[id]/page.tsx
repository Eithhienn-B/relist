import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft, GraduationCap, MapPin, ShieldAlert } from "lucide-react";
import { SiteHeader } from "@/components/site-header";
import { formatPrice, requireMember, timeAgo } from "@/lib/member";

export default async function ListingPage({ params }: PageProps<"/listings/[id]">) {
  const { id } = await params;
  const { supabase, membership } = await requireMember();
  if (!/^[0-9a-f-]{36}$/i.test(id)) notFound();

  const { data: listing } = await supabase
    .from("listings")
    .select("id, seller_id, title, description, price_cents, category, status, created_at, campuses(name, schools(short_name)), schools(short_name), listing_photos(path, moderation, position)")
    .eq("id", id)
    .order("position", { referencedTable: "listing_photos" })
    .maybeSingle();
  if (!listing) notFound();

  const paths = listing.listing_photos.map((p) => p.path);
  const { data: signed } = paths.length
    ? await supabase.storage.from("listing-photos").createSignedUrls(paths, 3600)
    : { data: [] };
  const isSeller = listing.seller_id === membership.user_id;
  const held = listing.listing_photos.filter((p) => p.moderation === "held").length;

  return (
    <>
      <SiteHeader email={membership.email} />
      <main className="mx-auto w-full max-w-5xl flex-1 px-4 py-6">
        <Link href="/" className="mb-4 inline-flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground">
          <ArrowLeft aria-hidden className="size-4" /> Browse
        </Link>
        <div className="grid gap-8 md:grid-cols-[3fr_2fr]">
          <div className="grid gap-2">
            {(signed ?? []).flatMap((s) => (s.signedUrl ? [{ path: s.path, url: s.signedUrl }] : [])).map((s, i) => (
              // eslint-disable-next-line @next/next/no-img-element -- short-lived signed URLs
              <img key={s.path} src={s.url} alt={i === 0 ? listing.title : `${listing.title}, photo ${i + 1}`}
                className="w-full rounded-xl bg-muted object-cover" />
            ))}
            {!paths.length && <div className="flex aspect-square items-center justify-center rounded-xl bg-muted text-sm text-muted-foreground">No photo</div>}
          </div>
          <div>
            <p className="text-3xl font-semibold tabular-nums">{formatPrice(listing.price_cents)}</p>
            <h1 className="mt-1 text-xl">{listing.title}</h1>
            <p className="mt-3 flex flex-wrap gap-x-3 gap-y-1 text-sm text-muted-foreground">
              <span className="inline-flex items-center gap-1">
                <MapPin aria-hidden className="size-4" />{listing.campuses.name} · {listing.campuses.schools.short_name}
              </span>
              <span className="inline-flex items-center gap-1">
                <GraduationCap aria-hidden className="size-4" />Sold by a {listing.schools?.short_name ?? "verified"} student
              </span>
            </p>
            <p className="mt-1 text-xs text-muted-foreground"><span className="capitalize">{listing.category}</span> · listed {timeAgo(listing.created_at)}</p>
            {listing.description && <p className="mt-5 text-sm leading-relaxed whitespace-pre-line">{listing.description}</p>}
            {isSeller && held > 0 && (
              <p className="mt-5 flex gap-2 rounded-lg border border-amber-500/40 bg-amber-500/10 p-3 text-sm">
                <ShieldAlert aria-hidden className="size-4 shrink-0 text-amber-600" />
                {held === 1 ? "One photo is" : `${held} photos are`} held for review and only visible to you.
              </p>
            )}
            {isSeller && listing.status !== "active" && (
              <p className="mt-3 text-sm text-muted-foreground capitalize">Status: {listing.status}</p>
            )}
            <p className="mt-6 rounded-lg bg-muted p-3 text-xs text-muted-foreground">
              Messaging and offers arrive in the next update. Meet on campus, in public.
            </p>
          </div>
        </div>
      </main>
    </>
  );
}
