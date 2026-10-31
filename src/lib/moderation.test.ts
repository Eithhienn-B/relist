import { afterEach, describe, expect, it, vi } from "vitest";
import { moderatePhoto, moderateText } from "./moderation";

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

describe("moderateText", () => {
  it("sends only the text and returns the categories that fired", async () => {
    vi.stubEnv("OPENAI_API_KEY", "test-key");
    const fetchSpy = vi.fn(async (_url: string, _init: RequestInit) => Response.json({
      results: [{ flagged: true, categories: { harassment: true, violence: false } }],
    }));
    vi.stubGlobal("fetch", fetchSpy);
    expect(await moderateText("you'll regret this")).toEqual({ flagged: true, categories: ["harassment"] });
    expect(JSON.parse(String(fetchSpy.mock.calls[0][1].body)).input).toEqual([{ type: "text", text: "you'll regret this" }]);
  });

  it("fails closed in production when the key is missing", async () => {
    vi.stubEnv("OPENAI_API_KEY", "");
    vi.stubEnv("NODE_ENV", "production");
    await expect(moderateText("hi")).rejects.toThrow("OPENAI_API_KEY");
  });

  it("throws on an API error so the message is not sent", async () => {
    vi.stubEnv("OPENAI_API_KEY", "test-key");
    vi.stubGlobal("fetch", vi.fn(async () => new Response("nope", { status: 503 })));
    await expect(moderateText("hi")).rejects.toThrow("503");
  });
});
