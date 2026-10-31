import { encode } from "uqr";

// QR modules as one SVG path, so React renders it (no innerHTML). High error correction: phone screens glare.
export function qrPath(text: string) {
  const { data, size } = encode(text, { ecc: "H", border: 2 });
  let d = "";
  data.forEach((row, y) => row.forEach((on, x) => { if (on) d += `M${x} ${y}h1v1h-1z`; }));
  return { size, d };
}
