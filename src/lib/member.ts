import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

// Every signed-in page needs a finished sign-up; send everyone else where they belong.
export async function requireMember() {
  const supabase = await createClient();
  const { data: auth } = await supabase.auth.getClaims();
  if (!auth) redirect("/login");
  const { data: membership } = await supabase
    .from("memberships")
    .select("user_id, email, campus_id, schools(short_name)")
    .eq("user_id", auth.claims.sub)
    .maybeSingle();
  if (!membership) redirect("/onboarding");
  return { supabase, membership };
}

export { formatPrice } from "./money";

export function timeAgo(iso: string, now = Date.now()) {
  const minutes = Math.round((now - new Date(iso).getTime()) / 60000);
  if (minutes < 1) return "just now";
  if (minutes < 60) return `${minutes}m ago`;
  if (minutes < 60 * 24) return `${Math.round(minutes / 60)}h ago`;
  return `${Math.round(minutes / 1440)}d ago`;
}
