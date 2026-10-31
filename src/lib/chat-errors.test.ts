import { describe, expect, it } from "vitest";
import { isUuid, userMessage } from "./chat-errors";

describe("userMessage", () => {
  it.each([
    ["42501", "This conversation has ended.", "This conversation has ended."],
    ["42501", "Your account is suspended.", "Your account is suspended."],
    ["54000", "Slow down a little. Try again in a minute.", "Slow down a little. Try again in a minute."],
    ["22023", "Messages are 1 to 2000 characters.", "Messages are 1 to 2000 characters."],
    ["P0002", "Listing not found", "Listing not found"],
    ["42501", "permission denied for function send_message", "fallback"],
    ["54000", "stack depth limit exceeded", "fallback"],
    ["23505", "duplicate key value violates unique constraint", "fallback"],
    [undefined, "fetch failed", "fallback"],
  ])("%s %s", (code, message, expected) => {
    expect(userMessage({ code, message }, "fallback")).toBe(expected);
  });
});

describe("isUuid", () => {
  it("accepts a uuid and rejects anything else", () => {
    expect(isUuid("174b1961-19d1-4026-bccd-38f9c9837dfa")).toBe(true);
    for (const v of ["", "abc", 42, null, { id: 1 }, "174b1961-19d1-4026-bccd-38f9c9837dfa/../x"]) expect(isUuid(v)).toBe(false);
  });
});
