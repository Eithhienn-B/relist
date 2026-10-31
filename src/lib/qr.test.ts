import { describe, expect, it } from "vitest";
import { encode } from "uqr";
import { qrPath } from "./qr";

describe("qrPath", () => {
  it("draws a 6-digit code as a version-1 QR (21 modules) plus a 2-module quiet zone", () => {
    expect(qrPath("123456").size).toBe(25);
  });

  it("draws exactly the dark modules the encoder produced", () => {
    const { data } = encode("123456", { ecc: "H", border: 2 });
    const dark = data.flat().filter(Boolean).length;
    expect(qrPath("123456").d.match(/M/g)?.length).toBe(dark);
    // top-left finder pattern starts right after the quiet zone
    expect(qrPath("123456").d.startsWith("M2 2h1v1h-1z")).toBe(true);
  });

  it("differs per code", () => {
    expect(qrPath("123456").d).not.toBe(qrPath("654321").d);
  });
});
