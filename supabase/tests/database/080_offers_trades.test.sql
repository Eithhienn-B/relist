-- Gate 2a: offers, handoff codes, trades, payment events, expiry.
-- Alice sells, Bob buys, Carol is another buyer on the same listing, Dave is a member with no thread,
-- Mallory never finished sign-up.
begin;
select plan(130);

select id as indy from public.campuses where name = 'Indianapolis' \gset
select tests.create_user('alice@purdue.edu') as alice \gset
select tests.create_user('bob@purdue.edu') as bob \gset
select tests.create_user('carol@purdue.edu') as carol \gset
select tests.create_user('dave@purdue.edu') as dave \gset
select tests.create_user('mallory@purdue.edu') as mallory \gset
insert into public.memberships (user_id, email, school_id, campus_id, grad_season, grad_year, is_18_plus) values
  (:'alice', 'alice@purdue.edu', 243780, :indy, 'spring', 2029, true),
  (:'bob', 'bob@purdue.edu', 243780, :indy, 'spring', 2029, true),
  (:'carol', 'carol@purdue.edu', 243780, :indy, 'spring', 2029, true),
  (:'dave', 'dave@purdue.edu', 243780, :indy, 'spring', 2029, true);

insert into public.listings (seller_id, school_id, campus_id, title, price_cents, category)
values (:'alice', 243780, :indy, 'Mini fridge', 6000, 'kitchen') returning id as fridge \gset
insert into public.listings (seller_id, school_id, campus_id, title, price_cents, category)
values (:'alice', 243780, :indy, 'Desk lamp', 2000, 'decor') returning id as lamp \gset
insert into public.listings (seller_id, school_id, campus_id, title, price_cents, category)
values (:'alice', 243780, :indy, 'Desk chair', 3000, 'furniture') returning id as chair \gset

select tests.authenticate_as(:'bob');
select public.open_thread(:'fridge') as t1 \gset
select public.open_thread(:'lamp') as t_lamp \gset
select public.open_thread(:'chair') as t_chair_bob \gset
select tests.authenticate_as(:'carol');
select public.open_thread(:'fridge') as t2 \gset
select public.open_thread(:'chair') as t_chair \gset
select tests.authenticate_as(:'dave');
select public.open_thread(:'chair') as t_dave \gset
reset role;

-- ===== Making offers =====
select tests.authenticate_as_anon();
select throws_ok(format('select public.make_offer(%L, 5000)', :'t1'), '42501', null, 'anon cannot make an offer');
select throws_ok('select * from public.offers', '42501', null, 'anon cannot read offers');
select throws_ok('select * from public.trades', '42501', null, 'anon cannot read trades');
select throws_ok('select * from public.payment_events', '42501', null, 'anon cannot read payment events');
select tests.authenticate_as(:'mallory');
select throws_ok(format('select public.make_offer(%L, 5000)', :'t1'), '42501', null, 'a non-member cannot make an offer');
select tests.authenticate_as(:'dave');
select throws_ok(format('select public.make_offer(%L, 5000)', :'t1'), '42501', 'Conversation not found',
  'a third member cannot make an offer in someone else''s thread');
select tests.authenticate_as(:'alice');
select throws_ok(format('select public.make_offer(%L, 5000)', :'t1'), '22023', 'You can''t make an offer on your own listing.',
  'a seller cannot offer on their own listing');
select tests.authenticate_as(:'bob');
select throws_ok(format('select public.make_offer(%L, 499)', :'t1'), '22023', 'Offers are $5.00 to $10000.',
  'an offer below the config minimum is refused');
select throws_ok(format('select public.make_offer(%L, null)', :'t1'), '22023', null, 'an offer needs an amount');
select public.make_offer(:'t1', 5000) as o1 \gset
select throws_ok(format('select public.make_offer(%L, 5200)', :'t1'), '22023', 'You already have an offer on this. Withdraw it first.',
  'one live offer per buyer per listing');
select throws_ok(
  format($$ insert into public.offers (thread_id, listing_id, buyer_id, seller_id, amount_cents) values (%L, %L, %L, %L, 100) $$,
         :'t1', :'fridge', :'bob', :'alice'),
  '42501', null, 'a member cannot insert an offer directly');
select throws_ok(format($$ update public.offers set state = 'accepted' where id = %L $$, :'o1'), '42501', null,
  'a member cannot update an offer directly');
select results_eq($$ select event, body from public.messages where offer_id is not null $$,
  $$ values ('offer'::text, 'Offered $50.00'::text) $$, 'the offer shows up in the thread as an event');
select tests.authenticate_as(:'carol');
select public.make_offer(:'t2', 5500) as o2 \gset
select public.make_offer(:'t_chair', 2500) as o_chair \gset
select tests.authenticate_as(:'dave');
select public.make_offer(:'t_dave', 2600) as o_dave \gset

-- ===== Who sees what =====
select tests.authenticate_as(:'bob');
select results_eq('select id from public.offers', format($$ values (%L::uuid) $$, :'o1'), 'the buyer sees only their own offer');
select tests.authenticate_as(:'carol');
select is((select count(*)::int from public.offers where id = :'o1'), 0, 'another buyer cannot see a competing offer');
select is((select count(*)::int from public.messages where thread_id = :'t1'), 0, 'another buyer cannot see the competing thread');
select tests.authenticate_as(:'alice');
select is((select count(*)::int from public.offers), 4, 'the seller sees every offer on their listings');

-- ===== Accepting =====
select tests.authenticate_as(:'dave');
select throws_ok(format('select public.accept_offer(%L)', :'o1'), 'P0002', 'Offer not found', 'a third member cannot accept an offer');
select throws_ok(format('select public.cancel_offer(%L)', :'o1'), 'P0002', 'Offer not found', 'a third member cannot cancel an offer');
select tests.authenticate_as(:'bob');
select throws_ok(format('select public.accept_offer(%L)', :'o1'), '42501', 'Only the seller can accept an offer.',
  'the buyer cannot accept their own offer');
select throws_ok(format('select public.decline_offer(%L)', :'o1'), '42501', 'Only the seller can decline an offer.',
  'the buyer cannot decline');
select throws_ok(format('select public.cancel_offer(%L)', :'o1'), '22023', null, 'a pending offer cannot be cancelled (withdraw it)');
select tests.authenticate_as(:'alice');
select throws_ok(format('select public.withdraw_offer(%L)', :'o1'), '42501', 'Only the buyer can withdraw an offer.',
  'the seller cannot withdraw');
select tests.authenticate_as_anon();
select throws_ok(format('select public.accept_offer(%L)', :'o1'), '42501', null, 'anon cannot accept an offer');
select tests.authenticate_as(:'alice');
select lives_ok(format('select public.accept_offer(%L)', :'o1'), 'the seller accepts');
select throws_ok(format('select public.accept_offer(%L)', :'o1'), '22023', 'This offer is already accepted.', 'accepting twice fails');
select throws_ok(format('select public.accept_offer(%L)', :'o2'), '22023', 'This offer is already declined.',
  'accepting a declined offer fails');
reset role;
select is((select status from public.listings where id = :'fridge'), 'pending', 'accept puts the listing on hold');
select is((select state from public.offers where id = :'o2'), 'declined', 'accept declines the other pending offers on the listing');
select ok((select expires_at between now() + interval '4 days' - interval '1 second' and now() + interval '4 days' from public.offers where id = :'o1'),
  'expires_at = accept + 4 days (config.offer_window)');
select results_eq($$ select kind, status, amount_cents from public.payment_events where offer_id = '$$ || :'o1' || $$' $$,
  $$ values ('authorize'::text, 'requested'::text, 5000) $$, 'accept asks the payment provider to authorize');
select is((select count(*)::int from private.handoff_codes where offer_id = :'o1'), 1, 'accept creates the handoff secret');

select tests.authenticate_as(:'carol');
select results_eq(format('select status from public.listings where id = %L', :'fridge'), $$ values ('pending'::text) $$,
  'a thread''s buyer still sees its listing after it goes pending (M2 bug fixed)');
select results_eq(format('select body from public.messages where thread_id = %L and event = %L', :'t2', 'declined'),
  $$ values ('Declined: the seller accepted another offer'::text) $$, 'the declined buyer gets an event in their thread');
select tests.authenticate_as(:'dave');
select is((select count(*)::int from public.listings where id = :'fridge'), 0, 'a member with no thread cannot see a pending listing');
select tests.authenticate_as(:'bob');
select throws_ok(format('select public.withdraw_offer(%L)', :'o1'), '22023', null, 'an accepted offer cannot be withdrawn');

-- ===== The handoff code is server-side only =====
select tests.authenticate_as(:'bob');
select throws_ok('select * from private.handoff_codes', '42501', null, 'a member cannot read handoff secrets');
select tests.authenticate_as_anon();
select throws_ok('select * from private.handoff_codes', '42501', null, 'anon cannot read handoff secrets');
select tests.authenticate_as_service();
select throws_ok('select * from private.handoff_codes', '42501', null, 'even the secret key cannot read handoff secrets');
reset role;
select ok(not has_table_privilege('authenticated', 'private.handoff_codes', 'select')
          and not has_table_privilege('anon', 'private.handoff_codes', 'select')
          and not has_table_privilege('service_role', 'private.handoff_codes', 'select'),
  'no client role has SELECT on handoff_codes');

select private.handoff_code_at(h.secret, private.handoff_window(now())) as code_now,
       private.handoff_code_at(h.secret, private.handoff_window(now()) - 1) as code_prev,
       private.handoff_code_at(h.secret, private.handoff_window(now()) - 2) as code_old
from private.handoff_codes h where h.offer_id = :'o1' \gset
select ok(:'code_now' ~ '^\d{6}$', 'the code is 6 digits');

select tests.authenticate_as(:'bob');
select is((select code from public.handoff_code(:'o1')), :'code_now', 'the buyer gets the current code');
select ok((select seconds_left between 1 and 30 from public.handoff_code(:'o1')), 'with the seconds left in its window');
select tests.authenticate_as(:'alice');
select throws_ok(format('select public.handoff_code(%L)', :'o1'), 'P0002', null, 'the seller cannot get the buyer''s code');
select tests.authenticate_as(:'dave');
select throws_ok(format('select public.handoff_code(%L)', :'o1'), 'P0002', null, 'a third member cannot get the code');

-- ===== The code can't be posted in chat (and a caught code is burned) =====
select tests.authenticate_as(:'bob');
select lives_ok(format('select public.can_send_message(%L)', :'t1'), 'the pre-check takes no body (a body check there was an oracle)');
select tests.authenticate_as_service();
select is((public.send_message(:'bob', :'t1', 'my code is ' || :'code_now', '{}', false)).id, null,
  'send_message refuses the current code (returns no message)');
reset role;
select is((select count(*)::int from public.messages where thread_id = :'t1' and body like '%' || :'code_now' || '%'), 0, 'nothing was posted');
select isnt(private.handoff_code_at((select secret from private.handoff_codes where offer_id = :'o1'), private.handoff_window(now())),
  :'code_now', 'the caught code is burned: the secret rotated');
select is((select failed_count from private.handoff_codes where offer_id = :'o1'), 1, 'and the offer takes a strike');
select private.handoff_code_at(h.secret, private.handoff_window(now())) as code_now,
       private.handoff_code_at(h.secret, private.handoff_window(now()) - 1) as code_prev,
       private.handoff_code_at(h.secret, private.handoff_window(now()) - 2) as code_old
from private.handoff_codes h where h.offer_id = :'o1' \gset
select tests.authenticate_as_service();
select is((public.send_message(:'alice', :'t1', 'is it ' || :'code_prev' || '?', '{}', false)).id, null,
  'the previous window''s code is caught too (either party)');
reset role;
select private.handoff_code_at(h.secret, private.handoff_window(now())) as code_now,
       private.handoff_code_at(h.secret, private.handoff_window(now()) - 1) as code_prev,
       private.handoff_code_at(h.secret, private.handoff_window(now()) - 2) as code_old
from private.handoff_codes h where h.offer_id = :'o1' \gset
select tests.authenticate_as_service();
select is((public.send_message(:'bob', :'t1',
  substr(:'code_now', 1, 2) || ' ' || substr(:'code_now', 3, 2) || '-' || substr(:'code_now', 5, 2), '{}', false)).id, null,
  'spacing the digits out doesn''t get past it');
reset role;
select private.handoff_code_at(h.secret, private.handoff_window(now())) as code_now,
       private.handoff_code_at(h.secret, private.handoff_window(now()) - 1) as code_prev,
       private.handoff_code_at(h.secret, private.handoff_window(now()) - 2) as code_old
from private.handoff_codes h where h.offer_id = :'o1' \gset
select is(private.digits(translate(:'code_now', '0123456789', '０１２３４５６７８９')), :'code_now', 'fullwidth digits fold to ASCII');
select is(private.digits(translate(:'code_now', '0123456789', '٠١٢٣٤٥٦٧٨٩')), :'code_now', 'Arabic-Indic digits fold to ASCII');
select tests.authenticate_as_service();
select isnt((public.send_message(:'bob', :'t1', 'see you at the library at 3', '{}', false)).id, null, 'normal messages still send');
reset role;
-- Reset the strikes the probes above added, so the redeem tests start clean.
update private.handoff_codes set failed_count = 0, failed_since = null where offer_id = :'o1';

-- ===== Redeeming =====
select tests.authenticate_as(:'bob');
select throws_ok(format('select public.redeem_handoff(%L, %L)', :'o1', :'code_now'), '42501', 'Only the seller can scan the handoff code.',
  'the buyer cannot redeem their own code');
select tests.authenticate_as(:'dave');
select throws_ok(format('select public.redeem_handoff(%L, %L)', :'o1', :'code_now'), 'P0002', null, 'a third member cannot redeem');
select tests.authenticate_as_anon();
select throws_ok(format('select public.redeem_handoff(%L, %L)', :'o1', :'code_now'), '42501', null, 'anon cannot redeem');
select tests.authenticate_as(:'alice');
select throws_ok(format('select public.redeem_handoff(%L, %L)', :'o1', :'code_now'), '22023',
  'The buyer''s payment hold is still processing. Try again in a moment.', 'no scan before the authorization succeeds');
reset role;
select id as ev1 from public.payment_events where offer_id = :'o1' and kind = 'authorize' \gset
select tests.authenticate_as_service();
select public.payment_result(:ev1, true, 'pi_stub_o1');
select tests.authenticate_as(:'alice');
select is(public.redeem_handoff(:'o1', :'code_old'), 'wrong_code', 'a code two windows old (60 s+) fails');
select is(public.redeem_handoff(:'o1', 'abcdef'), 'wrong_code', 'garbage fails');
reset role;
select is((select failed_count from private.handoff_codes where offer_id = :'o1'), 2, 'wrong codes are counted');
select is((select count(*)::int from public.trades), 0, 'no trade after wrong codes');
select tests.authenticate_as(:'alice');
select is(public.redeem_handoff(:'o1', :'code_prev'), 'completed', 'the previous 30 s window works (clock skew)');
select lives_ok(format('select public.redeem_handoff(%L, %L)', :'o1', :'code_prev'), 'a repeat scan reports completed (no error, no second trade)');
reset role;
select results_eq('select offer_id, amount_cents, fee_cents, captured_at is null from public.trades',
  format($$ values (%L::uuid, 5000, 250, true) $$, :'o1'), 'exactly one trade, 5% fee, captured_at waits for the provider');
select is((select state from public.offers where id = :'o1'), 'completed', 'the offer is completed');
select is((select status from public.listings where id = :'fridge'), 'sold', 'the listing is sold');
select is((select count(*)::int from private.handoff_codes where offer_id = :'o1'), 0, 'the secret is deleted after the trade');
select results_eq($$ select kind, amount_cents, fee_cents from public.payment_events where offer_id = '$$ || :'o1' || $$' order by id $$,
  $$ values ('authorize'::text, 5000, 0), ('capture'::text, 5000, 250) $$, 'authorize then capture with the fee');
select tests.authenticate_as(:'alice');
select throws_ok(format('select public.cancel_offer(%L)', :'o1'), '22023', null, 'a completed offer cannot be cancelled');
select tests.authenticate_as(:'carol');
select is((select count(*)::int from public.trades), 0, 'another buyer cannot see the trade');
select results_eq(format('select status from public.listings where id = %L', :'fridge'), $$ values ('sold'::text) $$,
  'the other buyer sees the listing as sold');
select tests.authenticate_as(:'bob');
select is((select count(*)::int from public.trades), 1, 'the buyer sees their trade');
select is((select count(*)::int from public.payment_events), 2, 'the buyer sees their payment events');
select throws_ok('select error from public.payment_events', '42501', null, 'provider error text is not exposed to clients');
reset role;
select id as ev_done from public.messages where thread_id = :'t1' and event = 'completed' \gset
select id as ev_acc from public.messages where thread_id = :'t1' and event = 'accepted' \gset
select tests.authenticate_as(:'dave');
select is((select count(*)::int from public.payment_events), 0, 'a third member sees no payment events');
select throws_ok(format('select public.report(%L, null, %s)', 'scam', :ev_done), 'P0002', null,
  'a third member cannot report an event');
select tests.authenticate_as(:'bob');
select throws_ok(format('select public.report(%L, null, %s)', 'scam', :ev_acc), 'P0002', null,
  'offer events cannot be reported as messages');

-- ===== Fee threshold (config: 500 bps over 1000 cents) =====
reset role;
select is(private.fee_cents(1000, 500, 1000), 0, '$10.00 pays no fee');
select is(private.fee_cents(1001, 500, 1000), 50, '$10.01 pays $0.50 (round half up)');
select is(private.fee_cents(1010, 500, 1000), 51, '$10.10 pays $0.51 (50.5 rounds up)');
select is(private.fee_cents(500, 500, 1000), 0, '$5.00 pays no fee');
select is(private.fee_cents(1000000, 500, 1000), 50000, '$10,000 pays $500');

-- ===== Expiry (fake time: move expires_at back) =====
select tests.authenticate_as(:'bob');
select public.make_offer(:'t_lamp', 1500) as o3 \gset
select tests.authenticate_as(:'alice');
select public.accept_offer(:'o3');
reset role;
select private.handoff_code_at(h.secret, private.handoff_window(now())) as code3 from private.handoff_codes h where h.offer_id = :'o3' \gset
-- Fake time: the trigger freezes the window, so step around it the way a test (never the app) can.
set local session_replication_role = replica;
update public.offers set expires_at = now() - interval '1 second' where id = :'o3';
set local session_replication_role = origin;
select tests.authenticate_as(:'alice');
select throws_ok(format('select public.redeem_handoff(%L, %L)', :'o3', :'code3'), '22023', 'This offer expired. The buyer wasn''t charged.',
  'a right code after expiry fails, even before the job runs');
select tests.authenticate_as(:'bob');
select throws_ok(format('select public.handoff_code(%L)', :'o3'), '22023', null, 'the buyer gets no code after expiry');
select tests.authenticate_as(:'alice');
select throws_ok('select private.expire_offers()', '42501', null, 'members cannot run the expiry job');
reset role;
select is(private.expire_offers(), 1, 'the job expires the overdue offer');
select is(private.expire_offers(), 0, 'running it again does nothing (idempotent)');
select is((select state from public.offers where id = :'o3'), 'expired', 'the offer is expired');
select is((select status from public.listings where id = :'lamp'), 'active', 'the listing goes back to active');
select is((select count(*)::int from public.payment_events where offer_id = :'o3' and kind = 'cancel'), 1, 'the authorization is cancelled once');
select results_eq(format('select sender_id is null, event from public.messages where offer_id = %L and event = %L', :'o3', 'expired'),
  $$ values (true, 'expired'::text) $$, 'expiry posts a system event');
select ok(exists (select 1 from cron.job where jobname = 'relist-expire-offers' and schedule = '* * * * *'), 'pg_cron runs the job every minute');

-- ===== Cancel after accept =====
select tests.authenticate_as(:'bob');
select public.make_offer(:'t_lamp', 1600) as o4 \gset
select tests.authenticate_as(:'alice');
select public.accept_offer(:'o4');
reset role;
select private.handoff_code_at(h.secret, private.handoff_window(now())) as code4 from private.handoff_codes h where h.offer_id = :'o4' \gset
select tests.authenticate_as(:'bob');
select lives_ok(format('select public.cancel_offer(%L)', :'o4'), 'the buyer can cancel after accept');
select tests.authenticate_as(:'alice');
select throws_ok(format('select public.redeem_handoff(%L, %L)', :'o4', :'code4'), '22023', null, 'a code cannot be redeemed after cancel');
reset role;
select is((select status from public.listings where id = :'lamp'), 'active', 'cancel puts the listing back');
select results_eq(format('select kind from public.payment_events where offer_id = %L order by id', :'o4'),
  $$ values ('authorize'::text), ('cancel'::text) $$, 'cancel cancels the authorization');

-- ===== Wrong codes are rate limited =====
select tests.authenticate_as(:'bob');
select public.make_offer(:'t_lamp', 1700) as o5 \gset
select tests.authenticate_as(:'alice');
select public.accept_offer(:'o5');
reset role;
select private.handoff_code_at(h.secret, private.handoff_window(now())) as code5,
       private.handoff_code_at(h.secret, private.handoff_window(now()) - 5) as bad5
from private.handoff_codes h where h.offer_id = :'o5' \gset
select id as ev5 from public.payment_events where offer_id = :'o5' and kind = 'authorize' \gset
select tests.authenticate_as_service();
select public.payment_result(:ev5, true, 'pi_stub_1');
select tests.authenticate_as(:'alice');
select public.redeem_handoff(:'o5', :'bad5') from generate_series(1, 5);
select throws_ok(format('select public.redeem_handoff(%L, %L)', :'o5', :'code5'), '54000', 'Too many wrong codes. Wait 10 minutes and try again.',
  'after 5 wrong codes even the right one is refused for 10 minutes');
reset role;
update private.handoff_codes set failed_since = now() - interval '11 minutes', total_failed = 20 where offer_id = :'o5';
select tests.authenticate_as(:'alice');
select throws_ok(format('select public.redeem_handoff(%L, %L)', :'o5', :'code5'), '54000', null,
  '20 wrong codes over the offer''s life lock it for good');
reset role;
update private.handoff_codes set total_failed = 0 where offer_id = :'o5';
select tests.authenticate_as(:'alice');
select is(public.redeem_handoff(:'o5', :'code5'), 'completed', 'the limit lifts after 10 minutes');

-- ===== State machine at the table (even the owner can't skip a step) =====
reset role;
select throws_ok(format($$ update public.offers set state = 'pending' where id = %L $$, :'o1'), '22023',
  'An offer can''t go from completed to pending.', 'completed -> pending is refused by the trigger');
select throws_ok(format($$ update public.offers set state = 'accepted' where id = %L $$, :'o3'), '22023', null, 'expired -> accepted is refused');
select throws_ok(format($$ update public.offers set state = 'completed' where id = %L $$, :'o_chair'), '22023', null,
  'pending -> completed (skipping accept) is refused');
select throws_ok(format($$ update public.offers set amount_cents = 1 where id = %L $$, :'o_chair'), '22023', 'Offers can''t be edited.',
  'the amount cannot change');
select throws_ok(
  format($$ insert into public.offers (thread_id, listing_id, buyer_id, seller_id, amount_cents, state, accepted_at, expires_at)
            values (%L, %L, %L, %L, 2000, 'accepted', now(), now()) $$, :'t_chair_bob', :'chair', :'bob', :'alice'),
  '22023', 'Offers start pending.', 'an offer cannot be born accepted (insert guard)');
select throws_ok(
  format($$ insert into public.offers (thread_id, listing_id, buyer_id, seller_id, amount_cents) values (%L, %L, %L, %L, 2000) $$,
         :'t_chair', :'chair', :'carol', :'alice'),
  '23505', null, 'one live offer per buyer per listing holds at the table');
select throws_ok(
  format($$ update public.offers set state = 'accepted', accepted_at = now(), expires_at = now() + interval '4 days'
            where id in (%L, %L) $$, :'o_chair', :'o_dave'),
  '23505', null, 'one accepted offer per listing holds at the table (parallel accepts; see scripts/parallel-accept.sh)');
select throws_ok(format($$ update public.offers set expires_at = expires_at + interval '1 day' where id = %L $$, :'o5'),
  '22023', 'The meetup window can''t be changed.', 'the 4-day window cannot be extended');
select tests.authenticate_as_service();
select throws_ok(format($$ insert into public.trades (offer_id, listing_id, buyer_id, seller_id, amount_cents, fee_cents)
                           values (%L, %L, %L, %L, 1, 0) $$, :'o_chair', :'chair', :'carol', :'alice'),
  '42501', null, 'the secret key cannot write trades directly');
select throws_ok('delete from public.payment_events', '42501', null, 'the secret key cannot delete payment events');
reset role;
select throws_ok(format('delete from auth.users where id = %L', :'bob'), '23503', null,
  'a user with trades cannot be deleted out from under the ledger');

-- ===== Blocks and suspension =====
-- A block made outside block_user still stops an accept.
insert into public.blocks (blocker_id, blocked_id) values (:'dave', :'alice');
select tests.authenticate_as(:'alice');
select throws_ok(format('select public.accept_offer(%L)', :'o_dave'), '42501', 'This conversation has ended.', 'a blocked pair cannot accept');
reset role;
delete from public.blocks where blocker_id = :'dave';
-- block_user ends the pair's live offers.
select tests.authenticate_as(:'alice');
select public.block_user(:'carol');
reset role;
select is((select state from public.offers where id = :'o_chair'), 'cancelled', 'blocking cancels the pair''s pending offer');
select tests.authenticate_as(:'carol');
select throws_ok(format('select public.make_offer(%L, 2500)', :'t_chair'), '42501', 'This conversation has ended.',
  'a blocked buyer cannot make an offer');
reset role;
update auth.users set banned_until = now() + interval '100 years' where id = :'dave';
select tests.authenticate_as(:'alice');
select throws_ok(format('select public.accept_offer(%L)', :'o_dave'), '42501', 'This buyer can''t trade right now.',
  'an offer from a suspended buyer cannot be accepted');
select tests.authenticate_as(:'dave');
select throws_ok(format('select public.withdraw_offer(%L)', :'o_dave'), '42501', 'Your account is suspended.',
  'a suspended user cannot act on offers');
reset role;
update auth.users set banned_until = null where id = :'dave';
update auth.users set banned_until = now() + interval '100 years' where id = :'alice';
select tests.authenticate_as(:'alice');
select throws_ok(format('select public.accept_offer(%L)', :'o_dave'), '42501', 'Your account is suspended.', 'a suspended seller cannot accept');
reset role;
update auth.users set banned_until = null where id = :'alice';
select tests.authenticate_as(:'dave');
select throws_ok(format('select public.make_offer(%L, 2700)', :'t_dave'), '22023', null, 'a buyer with a live offer cannot stack another');

-- ===== payment_result: server only, idempotent =====
reset role;
select id as ev_auth from public.payment_events where offer_id = :'o5' and kind = 'authorize' \gset
select id as ev_cap from public.payment_events where offer_id = :'o5' and kind = 'capture' \gset
select tests.authenticate_as(:'alice');
select throws_ok(format('select public.payment_result(%s, true, %L)', :ev_auth, 'pi_fake'), '42501', null,
  'a member cannot report a payment result');
select tests.authenticate_as_service();
select lives_ok(format('select public.payment_result(%s, true, %L)', :ev_auth, 'pi_stub_1'), 'the server records an authorization');
select lives_ok(format('select public.payment_result(%s, false, null, %L)', :ev_auth, 'late failure'), 'a second result for the same event is ignored');
select lives_ok(format('select public.payment_result(%s, true, %L)', :ev_cap, 'pi_stub_1'), 'the server records a capture');
reset role;
select results_eq(format('select status, provider_ref from public.payment_events where id = %s', :ev_auth),
  $$ values ('succeeded'::text, 'pi_stub_1'::text) $$, 'the first result sticks');
select is((select payment_ref from public.offers where id = :'o5'), 'pi_stub_1', 'authorize stores the payment reference on the offer');
select ok((select captured_at is not null from public.trades where offer_id = :'o5'), 'capture stamps captured_at');

-- A removed listing: hidden from its thread's buyer, and a scan can't turn it into a sale.
insert into public.listings (seller_id, school_id, campus_id, title, price_cents, category)
values (:'alice', 243780, :indy, 'Shelf', 1800, 'furniture') returning id as shelf \gset
select tests.authenticate_as(:'bob');
select public.make_offer(public.open_thread(:'shelf'), 1800) as o7 \gset
select tests.authenticate_as(:'alice');
select public.accept_offer(:'o7');
reset role;
select id as ev7 from public.payment_events where offer_id = :'o7' and kind = 'authorize' \gset
select private.handoff_code_at(h.secret, private.handoff_window(now())) as code7 from private.handoff_codes h where h.offer_id = :'o7' \gset
select tests.authenticate_as_service();
select public.payment_result(:ev7, true, 'pi_stub_7');
reset role;
update public.listings set status = 'removed' where id = :'shelf';
select tests.authenticate_as(:'bob');
select is((select count(*)::int from public.listings where id = :'shelf'), 0, 'a removed listing is hidden even from its thread''s buyer');
select tests.authenticate_as(:'alice');
select throws_ok(format('select public.redeem_handoff(%L, %L)', :'o7', :'code7'), '22023', 'This listing is no longer available.',
  'a scan cannot sell a removed listing');

reset role;
-- A failed authorization undoes the accept.
insert into public.listings (seller_id, school_id, campus_id, title, price_cents, category)
values (:'alice', 243780, :indy, 'Rug', 2500, 'decor') returning id as rug \gset
select tests.authenticate_as(:'bob');
select public.open_thread(:'rug') as t_rug \gset
select public.make_offer(:'t_rug', 2500) as o6 \gset
select tests.authenticate_as(:'alice');
select public.accept_offer(:'o6');
reset role;
select id as ev6 from public.payment_events where offer_id = :'o6' and kind = 'authorize' \gset
select tests.authenticate_as_service();
select public.payment_result(:ev6, false, null, 'card_declined');
reset role;
select is((select state from public.offers where id = :'o6'), 'cancelled', 'a declined card cancels the accepted offer');
select is((select status from public.listings where id = :'rug'), 'active', 'and frees the listing');

select * from finish();
rollback;
