import { describe, expect, it } from "vitest";
import { isEduEmail } from "./edu";

// Same cases as the auth hook tests in supabase/tests/database/020_signup.test.sql.
describe("isEduEmail", () => {
  it.each(["a@purdue.edu", "A@Sycamores.IndState.EDU", "a@unknown-college.edu"])("accepts %s", (email) => {
    expect(isEduEmail(email)).toBe(true);
  });
  it.each(["a@gmail.com", "a@purdue.edu.evil.com", "a@edu", "", "no-at-sign.edu"])("rejects %s", (email) => {
    expect(isEduEmail(email)).toBe(false);
  });
});
