import "server-only";
import { createClient } from "@supabase/supabase-js";
import type { Database } from "./database.types";

// Secret-key client: skips RLS. Server-only; used solely to store processed, moderated photos.
export function createAdminClient() {
  return createClient<Database>(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.SUPABASE_SECRET_KEY!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
