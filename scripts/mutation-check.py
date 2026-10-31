"""Gate 2a mutation checks: break one guard, reset the DB, run pgTAP, expect the named test to go red, restore.
Usage: python scripts/mutation-check.py   (local stack running; restores the migration and DB at the end)
"""
import pathlib
import subprocess

import sys

# M3 by default; `python scripts/mutation-check.py later` checks the later-ideas guards.
LATER = len(sys.argv) > 1 and sys.argv[1] == "later"
MIG = pathlib.Path("supabase/migrations/20261101000002_later_ideas.sql" if LATER else "supabase/migrations/20261101000001_offers.sql")
ORIGINAL = MIG.read_bytes().decode("utf8")

# (guard, text to find, replacement, test that must go red)
MUTATIONS = [
    ("handoff_code: buyer only",
     "where o.id = p_offer and o.buyer_id = v_uid;",
     "where o.id = p_offer and v_uid in (o.buyer_id, o.seller_id);",
     "the seller cannot get the buyer's code"),
    ("redeem: seller only",
     "  if v_offer.seller_id <> v_uid then\n    raise exception 'Only the seller can scan the handoff code.'",
     "  if false then\n    raise exception 'Only the seller can scan the handoff code.'",
     "the buyer cannot redeem their own code"),
    ("redeem: previous window accepted",
     "private.handoff_code_at(v_hc.secret, v_window - 1)) then",
     "private.handoff_code_at(v_hc.secret, v_window)) then",
     "the previous 30 s window works (clock skew)"),
    ("redeem: expiry",
     "  if v_offer.expires_at <= now() then\n    raise exception 'This offer expired.",
     "  if false then\n    raise exception 'This offer expired.",
     "a right code after expiry fails, even before the job runs"),
    ("send_message: code never posts",
     "  if char_length(v_digits) < 6 then\n    return false;",
     "  if true then\n    return false;",
     "send_message refuses the current code (returns no message)"),
    ("accept: blocked pair",
     "  if private.blocked_between(v_offer.buyer_id, v_offer.seller_id) then\n    raise exception 'This conversation has ended.' using errcode = '42501';\n  end if;\n  if private.is_suspended(v_offer.buyer_id)",
     "  if private.is_suspended(v_offer.buyer_id)",
     "a blocked pair cannot accept"),
    ("trigger: state machine",
     "  if new.state is distinct from old.state and (old.state, new.state) not in (",
     "  if false and (old.state, new.state) not in (",
     "completed -> pending is refused by the trigger"),
    ("offers RLS: parties only",
     "create policy \"parties see their offers\" on public.offers for select to authenticated\n  using ((select auth.uid()) in (buyer_id, seller_id));",
     "create policy \"parties see their offers\" on public.offers for select to authenticated\n  using (true);",
     "another buyer cannot see a competing offer"),
    ("redeem: one trade per scan (repeat scan)",
     "  if v_offer.state = 'completed' then\n    return 'completed';\n  end if;\n",
     "",
     "a repeat scan reports completed"),
]


LATER_MUTATIONS = [
    ("update_listing: price locked while accepted",
     "  if v_listing.status = 'pending' and p_price_cents is distinct from v_listing.price_cents then",
     "  if false then",
     "the price is locked while an offer is accepted"),
    ("unblock: blocker only",
     "delete from public.blocks b where b.blocker_id = v_uid and b.blocked_id = p_user;",
     "delete from public.blocks b where v_uid in (b.blocker_id, b.blocked_id) and p_user in (b.blocker_id, b.blocked_id);",
     "the blocked person cannot unblock"),
    # (Dropping the party `where` alone changes nothing: the case expressions only ever stamp the caller's column.)
    ("mark_thread_read: own receipt only",
     "      seller_read_at = case when t.seller_id = v_uid then now()",
     "      seller_read_at = case when v_uid is not null then now()",
     "each party only stamps their own receipt"),
    ("remove_listing: not while accepted",
     "  if v_listing.status = 'pending' then\n    raise exception 'An offer is accepted. Cancel the trade in the chat first.'",
     "  if false then\n    raise exception 'An offer is accepted. Cancel the trade in the chat first.'",
     "a listing with an accepted offer cannot be removed"),
    ("admin_reports: page cap",
     "limit least(greatest(coalesce(p_limit, 50), 1), 200);",
     "limit greatest(coalesce(p_limit, 50), 1);",
     "a page is capped at 200"),
]
if LATER:
    MUTATIONS = LATER_MUTATIONS

def run(cmd):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True, encoding="utf8", errors="replace")


results = []
try:
    for name, find, repl, test in MUTATIONS:
        assert ORIGINAL.count(find) == 1, f"mutation target not unique/found: {name}"
        MIG.write_bytes(ORIGINAL.replace(find, repl).encode("utf8"))
        reset = run("npx supabase db reset")
        res = run("npx supabase test db")
        out = res.stdout + res.stderr
        # pg_prove prints each failure as: # Failed test 12: "name"
        red = [line for line in out.splitlines() if "Failed test" in line and test in line]
        results.append((name, test, bool(red), reset.returncode))
        print(f"{'RED ' if red else 'MISS'} {name} -> {test!r}", flush=True)
finally:
    MIG.write_bytes(ORIGINAL.encode("utf8"))  # bytes: no CRLF rewrite on Windows
    run("npx supabase db reset")
    done = run("npx supabase test db")
    final = [l for l in (done.stdout + done.stderr).splitlines() if l.startswith("Result")]
    print("restored; suite:", final)

missed = [r for r in results if not r[2]]
print(f"{len(results) - len(missed)}/{len(results)} mutations caught")
raise SystemExit(1 if missed else 0)
