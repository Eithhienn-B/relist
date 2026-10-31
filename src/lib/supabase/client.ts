import { createBrowserClient } from "@supabase/ssr";
import type { Database } from "./database.types";

// Browser client (publishable key, the signed-in user's session from cookies). Used for realtime only.
export const createClient = () =>
  createBrowserClient<Database>(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!);
