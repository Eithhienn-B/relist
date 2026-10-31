// Browser-side resize before upload, only to save the student's data plan: the server still re-encodes,
// strips EXIF and moderates every photo (src/lib/photos.ts), so nothing here is trusted.
export const MAX_EDGE = 2048;

export function fitWithin(width: number, height: number, max = MAX_EDGE) {
  const scale = Math.min(1, max / Math.max(width, height));
  return { width: Math.round(width * scale), height: Math.round(height * scale) };
}

export async function shrinkPhoto(file: File): Promise<File> {
  try {
    // from-image applies the EXIF rotation, so a portrait phone photo stays upright.
    const bitmap = await createImageBitmap(file, { imageOrientation: "from-image" });
    const size = fitWithin(bitmap.width, bitmap.height);
    if (size.width === bitmap.width && file.size < 1_500_000) { bitmap.close(); return file; }
    const canvas = document.createElement("canvas");
    Object.assign(canvas, size);
    canvas.getContext("2d")!.drawImage(bitmap, 0, 0, size.width, size.height);
    bitmap.close();
    const blob = await new Promise<Blob | null>((r) => canvas.toBlob(r, "image/jpeg", 0.88));
    return blob && blob.size < file.size ? new File([blob], file.name.replace(/\.\w+$/, ".jpg"), { type: "image/jpeg" }) : file;
  } catch {
    return file; // an odd format or old browser: upload the original, the server handles it
  }
}
