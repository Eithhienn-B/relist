import Link from "next/link";
import { GraduationCap, MapPin, Search } from "lucide-react";
import { SiteHeader } from "@/components/site-header";
import { buttonVariants } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { formatPrice, requireMember, timeAgo } from "@/lib/member";
import { CampusFilter } from "./campus-filter";

export default async function Browse({ searchParams }: PageProps<"/">) {
  const { supabase, membership } = await requireMember();
  const params = await searchParams;
  const q = typeof params.q === "string" ? params.q.trim().slice(0, 100) : "";
  // Default filter: your home campus. "all" or any campus id overrides it.
  const campusParam = typeof params.campus === "string" ? params.campus : String(membership.campus_id ?? "all");
  const campusId = /^\d+$/.test(campusParam) ? Number(campusParam) : null;

  const { data: campuses } = await supabase.from("campuses").select("id, name, schools(short_name)").order("name");

  let query = supabase
    .from("listings")
    .select("id, title, price_cents, created_at, campuses(name), schools(short_name), listing_photos(path)")
    .eq("status", "active")
    .order("created_at", { ascending: false })
    .order("position", { referencedTable: "listing_photos" })
    .limit(1, { referencedTable: "listing_photos" })
    .limit(48);
  if (campusId) query = query.eq("campus_id", campusId);
  if (q) query = query.textSearch("search", q, { type: "websearch", config: "english" });
  const { data: listings, error } = await query;

  const paths = (listings ?? []).flatMap((l) => l.listing_photos.map((p) => p.path));
  const { data: signed } = paths.length
    ? await supabase.storage.from("listing-photos").createSignedUrls(paths, 600)
    : { data: [] };
  const urlFor = new Map((signed ?? []).map((s) => [s.path, s.signedUrl]));

  const campusOptions = (campuses ?? []).map((c) => ({ id: c.id, label: `${c.name} · ${c.schools.short_name}` }));
  const campusLabel = campusOptions.find((c) => c.id === campusId)?.label ?? "every campus";

  return (
    <>
      <SiteHeader email={membership.email} />
      <main className="mx-auto w-full max-w-6xl flex-1 px-4 py-6">
        <div className="mb-6 flex flex-col gap-3 sm:flex-row sm:items-center">
          <form className="relative flex-1" role="search">
            <input type="hidden" name="campus" value={campusId ?? "all"} />
            <Search aria-hidden className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground" />
            <Input name="q" type="search" defaultValue={q} placeholder="Search desks, textbooks, mini fridges…"
              aria-label="Search listings" className="h-10 pl-9" />
          </form>
          <CampusFilter options={campusOptions} value={campusId ? String(campusId) : "all"} q={q} />
        </div>

        <h1 className="mb-4 text-sm text-muted-foreground">
          {q ? <>Results for <span className="font-medium text-foreground">“{q}”</span> at </> : "Newest at "}
          <span className="font-medium text-foreground">{campusLabel}</span>
        </h1>

        {error ? (
          <p role="alert" className="text-sm text-destructive">Couldn&apos;t load listings. Refresh to try again.</p>
        ) : !listings?.length ? (
          <div className="rounded-2xl border border-dashed px-6 py-16 text-center">
            <p className="text-lg font-medium">{q ? "Nothing matches that yet." : "Nothing listed here yet."}</p>
            <p className="mt-1 text-sm text-muted-foreground">
              {q ? "Try fewer words or another campus." : "Be the first. It takes about a minute."}
            </p>
            <Link href="/sell" className={buttonVariants({ className: "press mt-5" })}>List something</Link>
          </div>
        ) : (
          <ul className="grid grid-cols-2 gap-x-4 gap-y-6 sm:grid-cols-3 lg:grid-cols-4">
            {listings.map((l, i) => {
              const src = l.listing_photos[0] && urlFor.get(l.listing_photos[0].path);
              return (
                <li key={l.id} className="card-in" style={{ "--i": i } as React.CSSProperties}>
                  <Link href={`/listings/${l.id}`} className="card-lift group block rounded-xl outline-offset-4">
                    <div className="aspect-square overflow-hidden rounded-xl bg-muted">
                      {src ? (
                        // eslint-disable-next-line @next/next/no-img-element -- short-lived signed URLs; next/image would cache them
                        <img src={src} alt="" className="size-full object-cover" loading={i < 8 ? "eager" : "lazy"} />
                      ) : (
                        <div className="flex size-full items-center justify-center text-xs text-muted-foreground">No photo</div>
                      )}
                    </div>
                    <div className="mt-2 flex items-baseline justify-between gap-2">
                      <p className="text-base font-semibold tabular-nums">{formatPrice(l.price_cents)}</p>
                      <p className="shrink-0 text-xs text-muted-foreground">{timeAgo(l.created_at)}</p>
                    </div>
                    <p className="truncate text-sm">{l.title}</p>
                    <p className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-0.5 text-xs text-muted-foreground">
                      <span className="inline-flex items-center gap-1"><MapPin aria-hidden className="size-3" />{l.campuses.name}</span>
                      <span className="inline-flex items-center gap-1">
                        <GraduationCap aria-hidden className="size-3" />
                        <span className="sr-only">Seller&apos;s school: </span>{l.schools?.short_name ?? "Student"}
                      </span>
                    </p>
                  </Link>
                </li>
              );
            })}
          </ul>
        )}
      </main>
    </>
  );
}
