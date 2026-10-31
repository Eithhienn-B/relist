"""Gate 2a mutation checks: break one guard, reset the DB, run pgTAP, expect the named test to go red, restore.
Usage: python scripts/mutation-check.py   (local stack running; restores the migration and DB at the end)
"""
import pathlib
import subprocess

MIG = pathlib.Path("supabase/migrations/20261101000001_offers.sql")
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
