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
  let photos: Buffer[];
  try {
    photos = await Promise.all(files.map(async (f) => processPhoto(Buffer.from(await f.arrayBuffer()))));
  } catch {
    return "One of those files isn't a photo we can read. Try JPG, PNG or WebP.";
  }
  const text = `${title}\n${description}`;
  // Fail closed: if moderation is unreachable, the photo is held for review instead of published.
  const verdicts = await Promise.all(
    photos.map((p) => moderatePhoto(p, text).catch(() => ({ flagged: true, categories: ["moderation_unavailable"] }))),
  );

  const supabase = await createClient();
  const { data: listing, error } = await supabase
    .rpc("create_listing", { p_title: title, p_description: description, p_price_cents: priceCents, p_category: category });
  if (error) return userMessage(error, "We couldn't save your listing. Try again.");

  // The listing id came from create_listing as this user, so it's theirs; store photos with the secret key.
  const admin = createAdminClient();
  const rows = [];
  for (const [i, webp] of photos.entries()) {
    const path = `${listing.id}/${crypto.randomUUID()}.webp`;
    const { error: uploadError } = await admin.storage.from("listing-photos").upload(path, webp, { contentType: "image/webp" });
    if (uploadError) return "Your listing is saved, but a photo failed to upload.";
    rows.push({ listing_id: listing.id, path, position: i, moderation: verdicts[i].flagged ? "held" : "approved", flags: verdicts[i].categories });
  }
  const { error: rowError } = await admin.from("listing_photos").insert(rows);
  if (rowError) return "Your listing is saved, but its photos failed to attach.";

  redirect(`/listings/${listing.id}`);
}
