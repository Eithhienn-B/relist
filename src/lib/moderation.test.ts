import { afterEach, describe, expect, it, vi } from "vitest";
import { moderatePhoto } from "./moderation";

afterEach(() => {
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

describe("moderatePhoto", () => {
  it("holds nothing while no API key is configured", async () => {
    vi.stubEnv("OPENAI_API_KEY", "");
    const fetchSpy = vi.fn();
    vi.stubGlobal("fetch", fetchSpy);
    expect(await moderatePhoto(Buffer.from("x"), "lamp")).toEqual({ flagged: false, categories: [] });
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("returns the categories that fired", async () => {
    vi.stubEnv("OPENAI_API_KEY", "test-key");
    vi.stubGlobal("fetch", vi.fn(async () => Response.json({
      results: [{ flagged: true, categories: { violence: true, sexual: false, "sexual/minors": false } }],
    })));
    expect(await moderatePhoto(Buffer.from("x"), "lamp")).toEqual({ flagged: true, categories: ["violence"] });
  });

  it("throws on an API error so the caller can hold the photo", async () => {
    vi.stubEnv("OPENAI_API_KEY", "test-key");
    vi.stubGlobal("fetch", vi.fn(async () => new Response("nope", { status: 500 })));
    await expect(moderatePhoto(Buffer.from("x"), "lamp")).rejects.toThrow("500");
  });
});
