"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export async function createMembership(_prev: string | undefined, formData: FormData) {
  const supabase = await createClient();
  const { error } = await supabase.rpc("create_membership", {
    p_grad_season: String(formData.get("grad_season")),
    p_grad_year: Number(formData.get("grad_year")),
    p_is_18_plus: formData.get("is_18_plus") === "on",
  });
  if (error) return error.message;
  redirect("/");
}
