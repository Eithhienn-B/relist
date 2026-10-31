"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

// admin_resolve_report refuses non-admins (42501), so this needs no check of its own.
export async function resolveReport(formData: FormData) {
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_resolve_report", {
    p_report: Number(formData.get("id")),
    p_action: String(formData.get("action")),
  });
  if (error) throw new Error(error.code === "42501" ? "Not allowed" : error.message);
  revalidatePath("/admin");
}
