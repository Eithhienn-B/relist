"use server";

import { redirect } from "next/navigation";
import { isUuid, userMessage } from "@/lib/chat-errors";
import { moderateText } from "@/lib/moderation";
import { parseDollars } from "@/lib/money";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

// Edits re-run moderation here, then the server (secret key) calls update_listing as the signed-in seller;
// update_listing re-checks ownership, status, price lock, minimum price and prohibited items.
export async function updateListing(listingId: string, _prev: string | undefined, formData: FormData) {
  if (!isUuid(listingId)) return "Listing not found";
  const supabase = await createClient();
  const { data: auth } = await supabase.auth.getClaims();
  if (!auth) return "Your session expired. Sign in again.";

  const title = String(formData.get("title") ?? "").trim();
  const description = String(formData.get("description") ?? "").trim();
  const category = String(formData.get("category") ?? "");
  const priceCents = parseDollars(String(formData.get("price") ?? ""));
  if (title.length < 3 || title.length > 80) return "Give it a title between 3 and 80 characters.";
  if (description.length > 2000) return "Keep the description under 2,000 characters.";
  if (priceCents === null) return "Enter a price like 25 or 25.50.";

  try {
    const verdict = await moderateText(`${title}\n${description}`);
    if (verdict.flagged) return "That wording was flagged by our safety check. Change it and try again.";
  } catch {
    return "Couldn't save right now. Try again in a moment."; // fail closed
  }

  const { error } = await createAdminClient().rpc("update_listing", {
    p_seller: auth.claims.sub, p_listing: listingId, p_title: title, p_description: description,
    p_price_cents: priceCents, p_category: category,
  });
  if (error) return userMessage(error, "Couldn't save your changes. Try again.");
  redirect(`/listings/${listingId}`);
}

export async function removeListing(listingId: string) {
  if (!isUuid(listingId)) return "Listing not found";
  const supabase = await createClient();
  const { error } = await supabase.rpc("remove_listing", { p_listing: listingId });
  if (error) return userMessage(error, "Couldn't take it down. Try again.");
  redirect("/");
}
