import { createClient } from "@supabase/supabase-js";
import type { Database } from "./database.types";

// Secret-key client: skips RLS. Server-only; used solely to store processed, moderated photos.
export function createAdminClient() {
  if (typeof window !== "undefined") throw new Error("createAdminClient is server-only");
  return createClient<Database>(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.SUPABASE_SECRET_KEY!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
