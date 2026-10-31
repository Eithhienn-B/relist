import { describe, expect, it } from "vitest";
import { detectOffPlatform, type OffPlatformKind } from "./nudge";

const cases: [string, OffPlatformKind[]][] = [
  // Ordinary chat, prices, rooms, times, dates, ISBNs, model numbers: no nudge.
  ["Is it still available?", []],
  ["$40 firm", []],
  ["Is $5 ok?", []],
  ["Bose QC35 for $120, can do $110", []],
  ["Meet at Wright Hall room 2104 at 3:30?", []],
  ["I'm in Tower 1204, floor 12", []],
  ["Pickup 11/02/2026 at 5pm works", []],
  ["ISBN 9780134685991, 10th edition", []],
  ["ISBN-10 0134685997", []],
  ["Order #4417820391 from Amazon, still sealed", []],
  ["I'm 6'2 in a red hoodie by the library", []],
  ["follow me @jake for more", []],
  ["5 stars @ the campus center", []],
  ["The cashier at Starbucks said hi", []],
  // Phone numbers
  ["Text me 317-555-0142", ["phone"]],
  ["(317) 555 0142 after class", ["phone"]],
  ["call 3175550142", ["phone"]],
  ["+1 317.555.0142", ["phone"]],
  // Emails, including spelled-out ones
  ["email me jake.s@gmail.com", ["email"]],
  ["my school email is benne525@purdue.edu", ["email"]],
  ["jake at gmail dot com", ["email"]],
  // Payment apps, cashtags, handles next to payment words, cash
  ["Venmo me", ["payment"]],
  ["can I pay with cash app?", ["payment"]],
  ["cashapp $jakeS", ["payment"]],
  ["just send $jakeS the money", ["payment"]],
  ["Zelle works for me", ["payment"]],
  ["paypal friends and family?", ["payment"]],
  ["send it to @jake-s", ["payment"]],
  ["@jake-s on V3nmo", ["payment"]],
  ["I'll bring cash", ["payment"]],
  ["can we do cash?", ["payment"]],
  // Several at once, in a fixed order
  ["Venmo @jake-s or text 317-555-0142", ["phone", "payment"]],
];

describe("detectOffPlatform", () => {
  it.each(cases)("%s", (text, expected) => {
    expect(detectOffPlatform(text)).toEqual(expected);
  });
});
