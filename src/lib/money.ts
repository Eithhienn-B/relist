// Client-safe (no server imports): used by client components too.
export const formatPrice = (cents: number) =>
  new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", minimumFractionDigits: cents % 100 ? 2 : 0 })
    .format(cents / 100);

// "$50", "50", "10.01" -> cents. Anything else (negative, 3 decimals, words) -> null.
export function parseDollars(input: string): number | null {
  const m = /^\s*\$?\s*(\d{1,7})(?:\.(\d{1,2}))?\s*$/.exec(input);
  if (!m) return null;
  return Number(m[1]) * 100 + Number((m[2] ?? "").padEnd(2, "0"));
}
