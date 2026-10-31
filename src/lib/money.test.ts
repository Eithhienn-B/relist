import { describe, expect, it } from "vitest";
import { parseDollars } from "./money";

describe("parseDollars", () => {
  it.each([
    ["50", 5000], ["$50", 5000], ["10.01", 1001], ["10.1", 1010], [" 7.5 ", 750], ["$ 12.00", 1200],
  ])("%s -> %i cents", (input, cents) => expect(parseDollars(input)).toBe(cents));

  it.each(["", "abc", "-5", "1.234", "5,00", "1e3", "12.", "$"])("rejects %j", (input) => expect(parseDollars(input)).toBeNull());
});
