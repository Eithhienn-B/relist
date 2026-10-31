import "server-only";

export type Moderation = { flagged: boolean; categories: string[] };

// OpenAI omni-moderation on each photo plus the listing text.
// shortcut: with no OPENAI_API_KEY this stub holds nothing in dev; waiting on key approval (see dev plan M1).
// In production a missing key throws, and the caller holds the photo (fail closed).
export async function moderatePhoto(webp: Buffer, text: string): Promise<Moderation> {
  const key = process.env.OPENAI_API_KEY;
  if (!key) {
    if (process.env.NODE_ENV === "production") throw new Error("OPENAI_API_KEY is not set");
    return { flagged: false, categories: [] };
  }

  const res = await fetch("https://api.openai.com/v1/moderations", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model: "omni-moderation-latest",
      input: [
        { type: "text", text },
        { type: "image_url", image_url: { url: `data:image/webp;base64,${webp.toString("base64")}` } },
      ],
    }),
  });
  if (!res.ok) throw new Error(`Moderation request failed: ${res.status}`);
  const { results } = (await res.json()) as { results: { flagged: boolean; categories: Record<string, boolean> }[] };
  if (!results?.length) throw new Error("Moderation returned no results");
  // Merge every result, so an image verdict counts even if the API returns one result per input.
  const categories = new Set(results.flatMap((r) => Object.entries(r.categories).filter(([, hit]) => hit).map(([name]) => name)));
  return { flagged: results.some((r) => r.flagged), categories: [...categories] };
}
