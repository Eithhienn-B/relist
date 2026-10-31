import sharp from "sharp";

export { MAX_PHOTO_BYTES, MAX_PHOTOS } from "./photos-limits";

// Re-encoding drops every metadata block (EXIF, GPS, XMP, ICC) because we never call
// withMetadata(); rotate() first bakes the EXIF orientation into the pixels.
export async function processPhoto(input: Buffer): Promise<Buffer> {
  return sharp(input, { limitInputPixels: 50_000_000 })
    .rotate()
    .resize({ width: 1600, height: 1600, fit: "inside", withoutEnlargement: true })
    .webp({ quality: 80 })
    .toBuffer();
}
