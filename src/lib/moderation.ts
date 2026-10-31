import "server-only";

export type Moderation = { flagged: boolean; categories: string[] };

type Input = { type: "text"; text: string } | { type: "image_url"; image_url: { url: string } };

// OpenAI omni-moderation. Without OPENAI_API_KEY this is a stub that flags nothing in dev;
// in production a missing key throws, and every caller treats a throw as "don't publish" (fail closed).
async function moderate(input: Input[]): Promise<Moderation> {
  const key = process.env.OPENAI_API_KEY;
  if (!key) {
    if (process.env.NODE_ENV === "production") throw new Error("OPENAI_API_KEY is not set");
    return { flagged: false, categories: [] };
  }

  const res = await fetch("https://api.openai.com/v1/moderations", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ model: "omni-moderation-latest", input }),
  });
  if (!res.ok) throw new Error(`Moderation request failed: ${res.status}`);
  const { results } = (await res.json()) as { results: { flagged: boolean; categories: Record<string, boolean> }[] };
  if (!results?.length) throw new Error("Moderation returned no results");
  // Merge every result, so an image verdict counts even if the API returns one result per input.
  const categories = new Set(results.flatMap((r) => Object.entries(r.categories).filter(([, hit]) => hit).map(([name]) => name)));
  return { flagged: results.some((r) => r.flagged), categories: [...categories] };
}

// Each photo plus the listing text. The caller holds the photo on a flag or a throw.
export const moderatePhoto = (webp: Buffer, text: string) =>
  moderate([
    { type: "text", text },
    { type: "image_url", image_url: { url: `data:image/webp;base64,${webp.toString("base64")}` } },
  ]);

// Chat messages. The caller holds a flagged message and refuses to send on a throw.
export const moderateText = (text: string) => moderate([{ type: "text", text }]);
