// Member-facing report reasons; keys match the reports.reason check in the chat migration.
export const REPORT_REASONS = {
  scam: "Scam or fraud",
  off_platform_payment: "Asked to pay outside ReList",
  harassment: "Harassment or threats",
  unsafe_meetup: "Unsafe meetup request",
  prohibited_item: "Prohibited item",
  fake_listing: "Fake or misleading listing",
  other: "Something else",
} as const;
