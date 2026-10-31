import { describe, expect, it } from "vitest";
import { fitWithin, shrinkPhoto } from "./shrink-photo";

describe("fitWithin", () => {
  it.each([
    [4032, 3024, 2048, 1536], // landscape phone photo
    [3024, 4032, 1536, 2048], // portrait
    [1200, 800, 1200, 800], // already small: unchanged, never enlarged
    [5000, 5000, 2048, 2048],
  ])("%i x %i -> %i x %i", (w, h, ew, eh) => expect(fitWithin(w, h)).toEqual({ width: ew, height: eh }));
});

describe("shrinkPhoto", () => {
  it("returns the original file when the browser can't decode it", async () => {
    const file = new File(["not an image"], "x.jpg", { type: "image/jpeg" });
    expect(await shrinkPhoto(file)).toBe(file); // createImageBitmap is missing in Node: same fallback path
  });
});
