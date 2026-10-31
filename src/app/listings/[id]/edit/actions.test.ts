import { beforeEach, describe, expect, it, vi } from "vitest";

// The secret-key path: moderation must pass before update_listing is called, and the seller comes from the session.
const adminRpc = vi.fn();
const moderate = vi.fn();
vi.mock("@/lib/supabase/admin", () => ({ createAdminClient: () => ({ rpc: adminRpc }) }));
vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({ auth: { getClaims: async () => ({ data: { claims: { sub: "seller-from-session" } } }) } }),
}));
vi.mock("@/lib/moderation", () => ({ moderateText: (t: string) => moderate(t) }));
vi.mock("next/navigation", () => ({ redirect: (url: string) => { throw new Error(`REDIRECT ${url}`); } }));

const { updateListing } = await import("./actions");
const id = "11111111-1111-1111-1111-111111111111";
const form = (fields: Record<string, string>) => {
  const f = new FormData();
  for (const [k, v] of Object.entries({ title: "Desk lamp", description: "", category: "decor", price: "20", ...fields })) f.set(k, v);
  return f;
};

beforeEach(() => { adminRpc.mockReset(); adminRpc.mockResolvedValue({ error: null }); moderate.mockReset(); });

describe("updateListing", () => {
  it("saves through update_listing as the session's user after moderation passes", async () => {
    moderate.mockResolvedValue({ flagged: false, categories: [] });
    await expect(updateListing(id, undefined, form({ seller: "someone-else" }))).rejects.toThrow(`REDIRECT /listings/${id}`);
    expect(adminRpc).toHaveBeenCalledWith("update_listing", expect.objectContaining({ p_seller: "seller-from-session", p_price_cents: 2000 }));
  });

  it("refuses flagged wording and never calls the database", async () => {
    moderate.mockResolvedValue({ flagged: true, categories: ["harassment"] });
    expect(await updateListing(id, undefined, form({}))).toMatch(/flagged/);
    expect(adminRpc).not.toHaveBeenCalled();
  });

  it("fails closed when moderation is down", async () => {
    moderate.mockRejectedValue(new Error("timeout"));
    expect(await updateListing(id, undefined, form({}))).toMatch(/Try again/);
    expect(adminRpc).not.toHaveBeenCalled();
  });

  it("passes the database's own reason through (e.g. price locked)", async () => {
    moderate.mockResolvedValue({ flagged: false, categories: [] });
    adminRpc.mockResolvedValueOnce({ error: { code: "22023", message: "An offer is accepted, so the price is locked until the trade completes or is cancelled." } });
    expect(await updateListing(id, undefined, form({}))).toMatch(/price is locked/);
  });

  it("rejects a bad price before moderation", async () => {
    expect(await updateListing(id, undefined, form({ price: "abc" }))).toMatch(/price/);
    expect(moderate).not.toHaveBeenCalled();
  });
});
