"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { moderateText } from "@/lib/moderation";
import { detectOffPlatform } from "@/lib/nudge";
import { createAdminClient } from "@/lib/supabase/admin";
import type { Tables } from "@/lib/supabase/database.types";
import { HANDOFF_CODE_REFUSED, isUuid, userMessage } from "@/lib/chat-errors";
import { REPORT_REASONS } from "@/lib/report-reasons";
import { createClient } from "@/lib/supabase/server";

export type Message = Tables<"messages">;

export async function startThread(listingId: string) {
  if (!isUuid(listingId)) return "Listing not found";
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("open_thread", { p_listing: listingId });
  if (error) return userMessage(error, "Couldn't start the conversation. Try again.");
  redirect(`/messages/${data}`);
}

export async function sendMessage(threadId: string, body: string): Promise<{ ok: true; message: Message } | { ok: false; error: string }> {
  if (!isUuid(threadId) || typeof body !== "string") return { ok: false, error: "Couldn't send. Try again." };
  const text = body.trim();
  if (!text || text.length > 2000) return { ok: false, error: "Messages are 1 to 2000 characters." };
  const supabase = await createClient();
  const { data: auth } = await supabase.auth.getClaims();
  if (!auth) return { ok: false, error: "Your session expired. Sign in again." };

  // Cheap checks (party, block, rate limit) before the moderation call; send_message re-checks under a lock.
  // The handoff-code check lives only in send_message: a body-taking pre-check was an oracle for the code.
  const { error: guard } = await supabase.rpc("can_send_message", { p_thread: threadId });
  if (guard) return { ok: false, error: userMessage(guard, "Couldn't send. Try again.") };

  let flags: string[];
  try {
    const verdict = await moderateText(text);
    flags = verdict.flagged ? (verdict.categories.length ? verdict.categories : ["flagged"]) : [];
  } catch {
    // Fail closed: no unmoderated text reaches the other person.
    return { ok: false, error: "Couldn't send right now. Try again in a moment." };
  }

  const { data, error } = await createAdminClient().rpc("send_message", {
    p_sender: auth.claims.sub,
    p_thread: threadId,
    p_body: text,
    p_flags: flags,
    p_nudge: detectOffPlatform(text).length > 0,
  });
  if (error) return { ok: false, error: userMessage(error, "Couldn't send. Try again.") };
  // null = it held a live handoff code; the code was burned (the buyer's code screen picks up the new one within 5 s).
  if (!data?.id) return { ok: false, error: HANDOFF_CODE_REFUSED };
  return { ok: true, message: data };
}

export async function blockUser(threadId: string, userId: string) {
  if (!isUuid(threadId) || !isUuid(userId)) return "Couldn't block. Try again.";
  const supabase = await createClient();
  const { error } = await supabase.rpc("block_user", { p_user: userId });
  if (error) return userMessage(error, "Couldn't block. Try again.");
  revalidatePath(`/messages/${threadId}`);
}

export async function report(target: { messageId: number } | { listingId: string }, reason: string, note: string) {
  if (typeof reason !== "string" || !Object.hasOwn(REPORT_REASONS, reason)) return "Pick a reason.";
  if (typeof note !== "string") note = "";
  const supabase = await createClient();
  const { error } = await supabase.rpc("report", {
    p_reason: reason,
    p_note: note.slice(0, 500),
    ...("messageId" in target ? { p_message_id: target.messageId } : { p_listing_id: target.listingId }),
  });
  return error ? userMessage(error, "Couldn't send the report. Try again.") : null;
}
