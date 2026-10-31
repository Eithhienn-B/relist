import { redirect } from "next/navigation";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { createClient } from "@/lib/supabase/server";
import { OnboardingForm } from "./form";

export default async function OnboardingPage() {
  const supabase = await createClient();
  const { data: auth } = await supabase.auth.getClaims();
  if (!auth) redirect("/login");
  const { data: membership } = await supabase
    .from("memberships")
    .select("user_id")
    .eq("user_id", auth.claims.sub)
    .maybeSingle();
  if (membership) redirect("/");

  const thisYear = new Date().getFullYear();
  const years = Array.from({ length: 8 }, (_, i) => thisYear + i);

  return (
    <main className="flex flex-1 items-center justify-center px-4 py-16">
      <Card className="w-full max-w-sm">
        <CardHeader>
          <p className="text-sm font-semibold tracking-tight text-muted-foreground">ReList</p>
          <CardTitle className="text-2xl">One last step</CardTitle>
          <CardDescription>We use this to show you listings from your campus first.</CardDescription>
        </CardHeader>
        <CardContent>
          <OnboardingForm years={years} />
        </CardContent>
      </Card>
    </main>
  );
}
