import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";
import type { Tables } from "@/lib/supabase/database.types";

// The SQL transitions write what the provider must do into payment_events (an outbox, one row per offer and kind).
// This module carries those out. M3 is a stub: no Stripe, no keys. M4 replaces only the four provider functions;
// the idempotency key `${offer_id}:${kind}` is what Stripe's Idempotency-Key header will get.
export type PaymentEvent = Pick<Tables<"payment_events">, "id" | "offer_id" | "kind" | "amount_cents" | "fee_cents">;
type Result = { ref: string };

export const idempotencyKey = (e: PaymentEvent) => `${e.offer_id}:${e.kind}`;

// M4: paymentIntents.create({ capture_method: "manual" }) on the seller's account.
export async function authorize(e: PaymentEvent): Promise<Result> {
  return { ref: `pi_stub_${e.offer_id}` };
}
// M4: paymentIntents.capture(ref, { application_fee_amount: e.fee_cents }).
export async function capture(e: PaymentEvent): Promise<Result> {
  return { ref: `pi_stub_${e.offer_id}` };
}
// M4: paymentIntents.cancel(ref). An uncaptured hold also releases on its own after ~7 days.
export async function cancel(e: PaymentEvent): Promise<Result> {
  return { ref: `pi_stub_${e.offer_id}` };
}
// M4: refunds.create({ payment_intent: ref, refund_application_fee: true }).
export async function refund(e: PaymentEvent): Promise<Result> {
  return { ref: `re_stub_${e.offer_id}` };
}

const provider = { authorize, capture, cancel, refund } as const;

// Carries out every requested event (for one offer, or the oldest few overall) and reports each result.
// Safe to call twice: payment_result ignores an event that's already been processed.
// shortcut: runs after each offer action, so a cancel queued by the expiry job waits for the next action; M4 adds a scheduled drain.
export async function processPayments(offerId?: string) {
  const db = createAdminClient();
  let query = db.from("payment_events").select("id, offer_id, kind, amount_cents, fee_cents")
    .eq("status", "requested").order("id").limit(20);
  if (offerId) query = query.eq("offer_id", offerId);
  const { data, error } = await query;
  if (error) throw new Error(`payment_events: ${error.message}`);
  for (const event of data) {
    let outcome: { p_ok: boolean; p_ref?: string; p_error?: string };
    try {
      outcome = { p_ok: true, p_ref: (await provider[event.kind as keyof typeof provider](event)).ref };
    } catch (err) {
      outcome = { p_ok: false, p_error: err instanceof Error ? err.message : String(err) };
    }
    const { error: saveError } = await db.rpc("payment_result", { p_event: event.id, ...outcome });
    if (saveError) throw new Error(`payment_result: ${saveError.message}`);
  }
  return data.length;
}
