import { redirect } from "next/navigation";
import { Card, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { createClient } from "@/lib/supabase/server";

export default async function Home() {
  const supabase = await createClient();
  const { data: auth } = await supabase.auth.getClaims();
  if (!auth) redirect("/login");
  const { data: membership } = await supabase
    .from("memberships")
    .select("email, schools(short_name), campuses(name)")
    .eq("user_id", auth.claims.sub)
    .maybeSingle();
  if (!membership) redirect("/onboarding");

  const home = membership.schools
    ? `${membership.schools.short_name} · ${membership.campuses?.name ?? ""}`
    : "No home campus yet";

  return (
    <main className="flex flex-1 items-center justify-center px-4 py-16">
      <Card className="w-full max-w-sm">
        <CardHeader>
          <p className="text-sm font-semibold tracking-tight text-muted-foreground">ReList</p>
          <CardTitle className="text-2xl">You&apos;re in</CardTitle>
          <CardDescription>
            {membership.email} · {home}. Listings arrive in the next milestone.
          </CardDescription>
        </CardHeader>
      </Card>
    </main>
  );
}
