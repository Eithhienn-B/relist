// Errors our SQL functions raise for the user (bad input, rate limit, ended/suspended, not found).
// Postgres raises some of the same codes itself ("permission denied for ..."); those stay generic.
export const userMessage = (error: { code?: string; message: string }, fallback: string) =>
  ["22023", "54000", "42501", "P0002"].includes(error.code ?? "") && !/^(permission denied|stack depth)/i.test(error.message)
    ? error.message : fallback;

export const isUuid = (v: unknown): v is string => typeof v === "string" && /^[0-9a-f-]{36}$/i.test(v);

export const HANDOFF_CODE_REFUSED =
  "Not sent: that's a handoff code. Never send it in chat or anywhere else. It only works shown in person, and it just changed.";
