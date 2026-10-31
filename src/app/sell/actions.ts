"use server";

import { redirect } from "next/navigation";
import { moderatePhoto } from "@/lib/moderation";
import { MAX_PHOTO_BYTES, MAX_PHOTOS, processPhoto } from "@/lib/photos";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

// Messages the database raises for the user (22023 bad input, 54000 rate limit); anything else stays generic.
const userMessage = (error: { code?: string; message: string }, fallback: string) =>
  error.code === "22023" || error.code === "54000" ? error.message : fallback;

export type LocationResult =
  | { ok: true; campus: string; school: string; expiresAt: string }
  | { ok: false; error: string };

export async function checkLocation(lat: number, lng: number, accuracy: number): Promise<LocationResult> {
  if (![lat, lng, accuracy].every(Number.isFinite)) return { ok: false, error: "That location doesn't look right. Try again." };
  const supabase = await createClient();
  const { data, error } = await supabase
    .rpc("check_location", { p_lat: lat, p_lng: lng, p_accuracy_m: accuracy })
    .single();
  if (error) return { ok: false, error: userMessage(error, "Couldn't check your location. Try again.") };
  if (!data.passed) {
    return {
      ok: false,
      error: data.reason === "low_accuracy"
        ? `Your location is only accurate to about ${Math.round(accuracy)} m. Try on your phone with location on.`
        : "You need to be within 5 miles of a campus to list. Try again when you're on or near campus.",
    };
  }
  return { ok: true, campus: data.campus_name!, school: data.school_name!, expiresAt: data.expires_at! };
}

export async function nearestCampus(lat: number, lng: number) {
  if (![lat, lng].every(Number.isFinite)) return null;
  const supabase = await createClient();
  const { data } = await supabase.rpc("nearest_campus", { p_lat: lat, p_lng: lng });
  return data;
}

export async function createListing(_prev: string | undefined, formData: FormData) {
  // Cheap checks before any photo work: signed in, and under the daily cap (the RPC re-checks both).
  const supabase = await createClient();
  const { data: auth } = await supabase.auth.getClaims();
  if (!auth) return "Your session expired. Sign in again.";
  const { count } = await supabase.from("listings").select("id", { count: "exact", head: true })
    .eq("seller_id", auth.claims.sub).gte("created_at", new Date(Date.now() - 86_400_000).toISOString());
  if ((count ?? 0) >= 20) return "You've hit today's listing limit (20).";

  const files = formData.getAll("photos").filter((f): f is File => f instanceof File && f.size > 0);
  if (!files.length) return "Add at least one photo.";
  if (files.length > MAX_PHOTOS) return `You can add up to ${MAX_PHOTOS} photos.`;
  if (files.some((f) => f.size > MAX_PHOTO_BYTES)) return "Each photo must be under 6 MB.";

  const title = String(formData.get("title") ?? "").trim();
  const description = String(formData.get("description") ?? "").trim();
  const category = String(formData.get("category") ?? "");
  const priceCents = Math.round(Number(formData.get("price")) * 100);
  if (title.length < 3 || title.length > 80) return "Give it a title between 3 and 80 characters.";
  if (description.length > 2000) return "Keep the description under 2,000 characters.";
  if (!Number.isFinite(priceCents)) return "Enter a price.";

  // Strip EXIF and moderate before anything is saved, so a bad file never leaves a half-made listing.
  // One at a time: a full-size decode can take a few hundred MB.
  const photos: Buffer[] = [];
  try {
    for (const f of files) photos.push(await processPhoto(Buffer.from(await f.arrayBuffer())));
  } catch {
    return "One of those files isn't a photo we can read. Try JPG, PNG or WebP.";
  }
  const text = `${title}\n${description}`;
  // Fail closed: if moderation is unreachable, the photo is held for review instead of published.
  const verdicts = await Promise.all(
    photos.map((p) => moderatePhoto(p, text).catch(() => ({ flagged: true, categories: ["moderation_unavailable"] }))),
  );

  const { data: listing, error } = await supabase
    .rpc("create_listing", { p_title: title, p_description: description, p_price_cents: priceCents, p_category: category });
  if (error) return userMessage(error, "We couldn't save your listing. Try again.");

  // The listing id came from create_listing as this user, so it's theirs; store photos with the secret key.
  const admin = createAdminClient();
  const rows = photos.map((_, i) => ({
    listing_id: listing.id,
    path: `${listing.id}/${crypto.randomUUID()}.webp`,
    position: i,
    moderation: verdicts[i].flagged ? "held" : "approved",
    flags: verdicts[i].categories,
  }));
  const uploads = await Promise.all(rows.map((r, i) =>
    admin.storage.from("listing-photos").upload(r.path, photos[i], { contentType: "image/webp" })));
  const failed = uploads.some((u) => u.error) || (await admin.from("listing_photos").insert(rows)).error;
  if (failed) {
    // Roll back so a retry doesn't leave a photo-less duplicate behind.
    await admin.storage.from("listing-photos").remove(rows.map((r) => r.path));
    await admin.from("listings").delete().eq("id", listing.id);
    return "Your photos didn't upload. Nothing was posted; try again.";
  }

  redirect(`/listings/${listing.id}`);
}
