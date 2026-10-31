import sharp from "sharp";
import { describe, expect, it } from "vitest";
import { processPhoto } from "./photos";

describe("processPhoto", () => {
  it("strips EXIF (including GPS) and re-encodes to webp", async () => {
    const withExif = await sharp({ create: { width: 40, height: 30, channels: 3, background: "#c00" } })
      .withExif({
        IFD0: { Artist: "Alice", Copyright: "secret" },
        IFD3: { GPSLatitudeRef: "N", GPSLatitude: "39/1 46/1 27/1", GPSLongitudeRef: "W", GPSLongitude: "86/1 10/1 33/1" },
      })
      .jpeg()
      .toBuffer();
    expect((await sharp(withExif).metadata()).exif).toBeDefined();

    const out = await processPhoto(withExif);
    const meta = await sharp(out).metadata();
    expect(meta.format).toBe("webp");
    expect(meta.exif).toBeUndefined();
    expect(meta.xmp).toBeUndefined();
    expect(out.includes(Buffer.from("secret"))).toBe(false);
  });

  it("bakes in EXIF orientation", async () => {
    const rotated = await sharp({ create: { width: 40, height: 20, channels: 3, background: "#00c" } })
      .withMetadata({ orientation: 6 })
      .jpeg()
      .toBuffer();
    const meta = await sharp(await processPhoto(rotated)).metadata();
    expect([meta.width, meta.height]).toEqual([20, 40]);
  });

  it("rejects files that aren't images", async () => {
    await expect(processPhoto(Buffer.from("not an image"))).rejects.toThrow();
  });
});
