import { notFound } from "next/navigation";
import { SiteHeader } from "@/components/site-header";
import { Button } from "@/components/ui/button";
import { requireMember, timeAgo } from "@/lib/member";
import { REPORT_REASONS } from "@/lib/report-reasons";
import { resolveReport } from "./actions";

// Bare report queue. Every admin_* function checks private.admins itself; a non-admin gets a 404.
export default async function AdminPage() {
  const { supabase, membership } = await requireMember();
  const [{ data: reports, error }, { data: stats }] = await Promise.all([
    supabase.rpc("admin_reports"),
    supabase.rpc("admin_stats").single(),
  ]);
  if (error?.code === "42501") notFound();
  if (error) throw new Error("Couldn't load reports");

  return (
    <>
      <SiteHeader email={membership.email} />
      <main className="mx-auto w-full max-w-4xl flex-1 px-4 py-6">
        <h1 className="text-2xl font-semibold tracking-tight">Reports</h1>
        {stats && (
          <dl className="mt-3 grid grid-cols-3 gap-3 text-sm">
            {[["Open reports", stats.open_reports], ["Off-platform nudges (7d)", stats.nudged_messages_7d], ["Held messages (7d)", stats.held_messages_7d]].map(([k, v]) => (
              <div key={k} className="rounded-lg border p-3"><dt className="text-muted-foreground">{k}</dt><dd className="text-xl font-semibold tabular-nums">{v}</dd></div>
            ))}
          </dl>
        )}
        {!reports?.length && <p className="mt-8 text-sm text-muted-foreground">Nothing reported. Quiet day.</p>}
        <ul className="mt-6 grid gap-3">
          {reports?.map((r) => (
            <li key={r.id} className={`rounded-xl border p-4 text-sm ${r.status === "open" ? "" : "opacity-60"}`}>
              <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
                <span className="font-medium">{r.source === "moderation" ? `Auto-held: ${r.flags.join(", ")}` : REPORT_REASONS[r.reason as keyof typeof REPORT_REASONS] ?? r.reason}</span>
                <span className="text-muted-foreground">{r.reporter_email ?? "moderation"} · {timeAgo(r.created_at)} · {r.status}</span>
              </div>
              {r.quoted && <blockquote className="mt-2 border-l-2 pl-3 whitespace-pre-wrap">{r.quoted}</blockquote>}
              {r.note && <p className="mt-2 text-muted-foreground">Note: {r.note}</p>}
              <p className="mt-2 text-xs text-muted-foreground">
                Listing: {r.listing_title ?? "none"}{r.listing_status ? ` (${r.listing_status})` : ""} · User: {r.reported_email ?? "unknown"}{r.reported_suspended ? " (suspended)" : ""}
              </p>
              {r.status === "open" && (
                <form action={resolveReport} className="mt-3 flex flex-wrap gap-2">
                  <input type="hidden" name="id" value={r.id} />
                  <Button type="submit" name="action" value="dismiss" size="sm" variant="outline">Dismiss</Button>
                  {r.listing_id && r.listing_status !== "removed" && (
                    <Button type="submit" name="action" value="hide_listing" size="sm" variant="outline">Hide listing</Button>
                  )}
                  {r.reported_user_id && !r.reported_suspended && (
                    <Button type="submit" name="action" value="suspend_user" size="sm" variant="destructive">Suspend user</Button>
                  )}
                </form>
              )}
            </li>
          ))}
        </ul>
      </main>
    </>
  );
}
