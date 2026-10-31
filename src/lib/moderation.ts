export type Moderation = { flagged: boolean; categories: string[] };

// OpenAI omni-moderation on each photo plus the listing text.
// shortcut: with no OPENAI_API_KEY this stub holds nothing; waiting on key approval (see dev plan M1).
export async function moderatePhoto(webp: Buffer, text: string): Promise<Moderation> {
  const key = process.env.OPENAI_API_KEY;
  if (!key) return { flagged: false, categories: [] };

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
  const [result] = results;
  return {
    flagged: result.flagged,
    categories: Object.entries(result.categories).filter(([, hit]) => hit).map(([name]) => name),
  };
}
