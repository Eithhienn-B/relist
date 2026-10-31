import { beforeEach, describe, expect, it, vi } from "vitest";

// A fake secret-key client: records which events were read and what results were saved.
const calls: { filters: [string, unknown][]; results: unknown[] } = { filters: [], results: [] };
let rows: unknown[] = [];
let rpcError: { message: string } | null = null;
vi.mock("@/lib/supabase/admin", () => ({
  createAdminClient: () => {
    const q = {
      select: () => q, order: () => q, limit: () => q,
      eq: (col: string, val: unknown) => { calls.filters.push([col, val]); return q; },
      then: (resolve: (v: unknown) => void) => resolve({ data: rows, error: null }),
    };
    return {
      from: () => q,
      rpc: async (name: string, args: unknown) => { calls.results.push([name, args]); return { error: rpcError }; },
    };
  },
}));

const { processPayments, idempotencyKey } = await import("./payments");
const offer = "11111111-1111-1111-1111-111111111111";

beforeEach(() => { calls.filters = []; calls.results = []; rows = []; rpcError = null; });

describe("payments stub", () => {
  it("authorizes then captures, reporting each result to payment_result with the stub reference", async () => {
    rows = [
      { id: 1, offer_id: offer, kind: "authorize", amount_cents: 5000, fee_cents: 0 },
      { id: 2, offer_id: offer, kind: "capture", amount_cents: 5000, fee_cents: 250 },
    ];
    expect(await processPayments(offer)).toBe(2);
    expect(calls.filters).toEqual([["status", "requested"], ["offer_id", offer]]);
    expect(calls.results).toEqual([
      ["payment_result", { p_event: 1, p_ok: true, p_ref: `pi_stub_${offer}` }],
      ["payment_result", { p_event: 2, p_ok: true, p_ref: `pi_stub_${offer}` }],
    ]);
  });

  it("only reads requested events, so a second run does nothing", async () => {
    expect(await processPayments(offer)).toBe(0);
    expect(calls.results).toEqual([]);
  });

  it("reports a provider failure instead of throwing, so the database can undo the accept", async () => {
    rows = [{ id: 3, offer_id: offer, kind: "bogus", amount_cents: 100, fee_cents: 0 }];
    await processPayments();
    expect(calls.results).toEqual([["payment_result", { p_event: 3, p_ok: false, p_error: expect.any(String) }]]);
  });

  it("throws if a result can't be saved (nothing is silently lost)", async () => {
    rows = [{ id: 4, offer_id: offer, kind: "cancel", amount_cents: 100, fee_cents: 0 }];
    rpcError = { message: "down" };
    await expect(processPayments()).rejects.toThrow("payment_result: down");
  });

  it("uses one idempotency key per offer and kind", () => {
    expect(idempotencyKey({ id: 9, offer_id: offer, kind: "capture", amount_cents: 1, fee_cents: 0 })).toBe(`${offer}:capture`);
  });
});
