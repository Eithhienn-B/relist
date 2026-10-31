#!/usr/bin/env bash
# Gate 2a: two sessions accept two different offers on the same listing at the same moment.
# Exactly one must win; the other must fail with a clear error (not a deadlock, not a second accept).
# Usage: bash scripts/parallel-accept.sh   (local stack running; leaves no rows behind)
set -euo pipefail
DB=supabase_db_relist
psql() { docker exec -i "$DB" psql -U postgres -v ON_ERROR_STOP=1 -qtA "$@"; }

ids=$(psql <<'SQL'
select tests.create_user('par-s@purdue.edu') || ',' || tests.create_user('par-a@purdue.edu') || ',' || tests.create_user('par-b@purdue.edu');
SQL
)
IFS=, read -r S A B <<<"$ids"
L=$(psql -c "
insert into public.memberships (user_id, email, school_id, campus_id, grad_season, grad_year, is_18_plus)
select u, e, 243780, (select id from public.campuses where name = 'Indianapolis'), 'spring', 2029, true
from (values ('$S'::uuid, 'par-s@purdue.edu'), ('$A'::uuid, 'par-a@purdue.edu'), ('$B'::uuid, 'par-b@purdue.edu')) v(u, e);
insert into public.listings (seller_id, school_id, campus_id, title, price_cents, category)
values ('$S', 243780, (select id from public.campuses where name = 'Indianapolis'), 'Race lamp', 2000, 'decor') returning id;" | tail -1)

as_user() { echo "select set_config('request.jwt.claims', json_build_object('sub', '$1', 'role', 'authenticated')::text, false); set role authenticated;"; }
OA=$( (as_user "$A"; echo "select public.make_offer(public.open_thread('$L'), 2000);") | psql | tail -1)
OB=$( (as_user "$B"; echo "select public.make_offer(public.open_thread('$L'), 2100);") | psql | tail -1)

# Each session sleeps inside its transaction after accepting, so the two overlap.
accept() { (as_user "$S"; echo "begin; select public.accept_offer('$1'); select pg_sleep(1); commit;") | psql 2>&1 | grep -E 'ERROR|accept' || true; }
accept "$OA" > /tmp/par-a.txt & accept "$OB" > /tmp/par-b.txt & wait

echo "session A: $(cat /tmp/par-a.txt)"
echo "session B: $(cat /tmp/par-b.txt)"
result=$(psql -c "select count(*) filter (where state = 'accepted') || ' accepted, ' || count(*) filter (where state = 'declined') || ' declined'
                  from public.offers where listing_id = '$L';")
echo "offers: $result"
psql -c "delete from public.payment_events where offer_id in ('$OA', '$OB'); delete from auth.users where id in ('$S', '$A', '$B');" >/dev/null
grep -q deadlock /tmp/par-a.txt /tmp/par-b.txt && { echo "FAIL: deadlock"; exit 1; }
[ "$result" = "1 accepted, 1 declined" ] && echo "PASS: one accept wins, the other fails cleanly" || { echo "FAIL"; exit 1; }
