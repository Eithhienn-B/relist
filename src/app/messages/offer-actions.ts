"use server";

import { revalidatePath } from "next/cache";
import { isUuid, userMessage } from "@/lib/chat-errors";
import { processPayments } from "@/lib/payments";
import { createClient } from "@/lib/supabase/server";

type Result = { ok: true } | { ok: false; error: string };

// Every transition runs as the signed-in user (the SQL function checks who and what state), then the payments
// module carries out whatever the transition queued (authorize, capture, cancel).
async function run(fn: "accept_offer" | "decline_offer" | "withdraw_offer" | "cancel_offer", offerId: string, fallback: string): Promise<Result> {
  if (!isUuid(offerId)) return { ok: false, error: fallback };
  const supabase = await createClient();
  const { error } = await supabase.rpc(fn, { p_offer: offerId });
  if (error) return { ok: false, error: userMessage(error, fallback) };
  await settle(offerId);
  return { ok: true };
}

async function settle(offerId: string) {
  try {
    await processPayments(offerId);
    await processPayments(); // also anything the expiry job queued
  } catch (err) {
    // The events stay 'requested' and the next action retries them; the transition itself already committed.
    console.error("payments", err);
  }
}

export async function makeOffer(threadId: string, amountCents: number): Promise<Result> {
  if (!isUuid(threadId) || !Number.isInteger(amountCents)) return { ok: false, error: "Enter an amount like 25 or 25.50." };
  const supabase = await createClient();
  const { error } = await supabase.rpc("make_offer", { p_thread: threadId, p_amount_cents: amountCents });
  return error ? { ok: false, error: userMessage(error, "Couldn't send the offer. Try again.") } : { ok: true };
}

export const acceptOffer = async (id: string) => run("accept_offer", id, "Couldn't accept. Try again.");
export const declineOffer = async (id: string) => run("decline_offer", id, "Couldn't decline. Try again.");
export const withdrawOffer = async (id: string) => run("withdraw_offer", id, "Couldn't withdraw. Try again.");
export const cancelOffer = async (id: string) => run("cancel_offer", id, "Couldn't cancel. Try again.");

export async function redeemCode(offerId: string, code: string): Promise<Result> {
  if (!isUuid(offerId) || typeof code !== "string") return { ok: false, error: "Enter the 6-digit code." };
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("redeem_handoff", { p_offer: offerId, p_code: code.slice(0, 20) });
  if (error) return { ok: false, error: userMessage(error, "Couldn't check the code. Try again.") };
  if (data === "wrong_code") return { ok: false, error: "That code didn't match. Ask the buyer to show the code on their screen now." };
  await settle(offerId);
  revalidatePath(`/offers/${offerId}`);
  return { ok: true };
}
