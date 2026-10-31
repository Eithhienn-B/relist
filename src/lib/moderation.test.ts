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

  it("fails closed in production when the key is missing", async () => {
    vi.stubEnv("OPENAI_API_KEY", "");
    vi.stubEnv("NODE_ENV", "production");
    await expect(moderatePhoto(Buffer.from("x"), "lamp")).rejects.toThrow("OPENAI_API_KEY");
  });

  it("flags when any per-input result is flagged (e.g. the image, not the text)", async () => {
    vi.stubEnv("OPENAI_API_KEY", "test-key");
    vi.stubGlobal("fetch", vi.fn(async () => Response.json({
      results: [
        { flagged: false, categories: { violence: false } },
        { flagged: true, categories: { "sexual/minors": true } },
      ],
    })));
    expect(await moderatePhoto(Buffer.from("x"), "lamp")).toEqual({ flagged: true, categories: ["sexual/minors"] });
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
