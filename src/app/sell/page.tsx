import { SiteHeader } from "@/components/site-header";
import { requireMember } from "@/lib/member";
import { SellForm } from "./sell-form";

export default async function SellPage() {
  const { supabase, membership } = await requireMember();

  // Reuse a passing check that's still inside location_check_ttl, so sellers don't re-check per item.
  const [{ data: config }, { data: check }] = await Promise.all([
    supabase.from("config").select("location_check_ttl, min_price_cents").is("school_id", null).single(),
    supabase
      .from("location_checks")
      .select("checked_at, campuses(name, schools(short_name))")
      .eq("passed", true)
      .order("checked_at", { ascending: false })
      .limit(1)
      .maybeSingle(),
  ]);
  const current = stillValid(check, config?.location_check_ttl);

  return (
    <>
      <SiteHeader email={membership.email} />
      <main className="mx-auto w-full max-w-xl flex-1 px-4 py-8">
        <h1 className="text-2xl font-semibold tracking-tight">List an item</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Every listing is tied to the campus you&apos;re near, so buyers know it&apos;s a short walk away.
        </p>
        <SellForm initialCheck={current} minPrice={(config?.min_price_cents ?? 500) / 100} />
      </main>
    </>
  );
}

type Check = { checked_at: string; campuses: { name: string; schools: { short_name: string } } | null } | null;

// The passing check still inside location_check_ttl (Postgres interval text like "24:00:00"), if any.
function stillValid(check: Check, ttl: string | undefined) {
  const ttlHours = Number(ttl?.split(":")[0] ?? 24);
  // Only "HH:MM:SS" parses; anything else (e.g. "1 day") just asks for a fresh check.
  if (!check?.campuses || !Number.isFinite(ttlHours)) return undefined;
  const expiresAt = new Date(new Date(check.checked_at).getTime() + ttlHours * 3600_000);
  if (expiresAt.getTime() <= Date.now()) return undefined;
  return { ok: true as const, campus: check.campuses.name, school: check.campuses.schools.short_name, expiresAt: expiresAt.toISOString() };
}
