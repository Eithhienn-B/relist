// Off-platform contact and payment detection for chat. With no cash path, a Venmo handle or a phone
// number is how a trade leaves ReList (and how most marketplace scams start). We nudge, never block.
// Shared by the composer (warns before sending) and the server action (stores messages.nudge).

export type OffPlatformKind = "phone" | "email" | "payment";

// US numbers: area code and exchange start 2-9, so prices, rooms, ISBNs and order numbers don't match.
const PHONE = /(?<![\d#$])(?:\+?1[\s.-]?)?(?:\(\s*[2-9]\d{2}\s*\)|[2-9]\d{2})[\s.-]?[2-9]\d{2}[\s.-]?\d{4}(?!\d)/;
const EMAIL = /[\w.+-]+@[a-z0-9-]+(?:\.[a-z0-9-]+)*\.[a-z]{2,}|\b\w+\s*(?:at|\(at\))\s*(?:gmail|yahoo|outlook|hotmail|icloud|aol|proton(?:mail)?|[a-z]+\.edu)\s*(?:dot|\.)\s*(?:com|edu|net|org|me)\b/i;
// Leetspeak-tolerant app names: v3nmo, z3lle, payp4l.
const APPS = /\b(?:v[e3]nm[o0]|z[e3]ll[e3]|payp[a4]l|cash\s?app|apple\s?pay|chime)\b/i;
const CASHTAG = /(?<![\w$])\$[a-z][\w-]{1,19}\b/i;
const HANDLE = /(?<![\w.])@[a-z][\w.-]{1,29}/i;
const PAY_WORDS = /\b(?:pay|paying|paid|send|sent|transfer|money)\b/i;
const CASH = /\bcash\b/i; // no cash trades in the pilot, so "bring cash" is a leak too

export function detectOffPlatform(text: string): OffPlatformKind[] {
  const kinds: OffPlatformKind[] = [];
  if (PHONE.test(text)) kinds.push("phone");
  if (EMAIL.test(text)) kinds.push("email");
  if (APPS.test(text) || CASHTAG.test(text) || (HANDLE.test(text) && PAY_WORDS.test(text)) || CASH.test(text)) {
    kinds.push("payment");
  }
  return kinds;
}
