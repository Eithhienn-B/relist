-- Later ideas: edit/remove a listing, unblock, the "ended" event, read receipts, admin paging and filters.
-- Alice sells, Bob buys, Carol is a third member, Dave is an admin.
begin;
select plan(37);

select id as indy from public.campuses where name = 'Indianapolis' \gset
select tests.create_user('alice@purdue.edu') as alice \gset
select tests.create_user('bob@purdue.edu') as bob \gset
select tests.create_user('carol@purdue.edu') as carol \gset
select tests.create_user('dave@purdue.edu') as dave \gset
insert into public.memberships (user_id, email, school_id, campus_id, grad_season, grad_year, is_18_plus) values
  (:'alice', 'alice@purdue.edu', 243780, :indy, 'spring', 2029, true),
  (:'bob', 'bob@purdue.edu', 243780, :indy, 'spring', 2029, true),
  (:'carol', 'carol@purdue.edu', 243780, :indy, 'spring', 2029, true),
  (:'dave', 'dave@purdue.edu', 243780, :indy, 'spring', 2029, true);
insert into private.admins (user_id) values (:'dave');
insert into public.listings (seller_id, school_id, campus_id, title, price_cents, category)
values (:'alice', 243780, :indy, 'Mini fridge', 6000, 'kitchen') returning id as fridge \gset
insert into public.listings (seller_id, school_id, campus_id, title, price_cents, category)
values (:'alice', 243780, :indy, 'Desk lamp', 2000, 'decor') returning id as lamp \gset

-- ===== Edit =====
select tests.authenticate_as(:'alice');
select throws_ok(format($$ select public.update_listing(%L, %L, 'Big fridge', '', 6000, 'kitchen') $$, :'alice', :'fridge'),
  '42501', null, 'a member cannot call update_listing (edits go through moderation on the server)');
select throws_ok(format($$ update public.listings set title = 'x' where id = %L $$, :'fridge'), '42501', null,
  'a member cannot update a listing directly');
select tests.authenticate_as_service();
select is((public.update_listing(:'alice', :'fridge', ' Big fridge ', 'Cold', 5500, 'kitchen')).title, 'Big fridge', 'the seller can edit (via the server)');
select throws_ok(format($$ select public.update_listing(%L, %L, 'Mine now', '', 100, 'kitchen') $$, :'bob', :'fridge'),
  'P0002', null, 'nobody else can edit the listing');
select throws_ok(format($$ select public.update_listing(%L, %L, 'Fridge and beer', '', 5500, 'kitchen') $$, :'alice', :'fridge'),
  '22023', 'Alcohol isn''t allowed on ReList.', 'edits re-run the prohibited-items check');
select throws_ok(format($$ select public.update_listing(%L, %L, 'Fridge', '', 100, 'kitchen') $$, :'alice', :'fridge'),
  '22023', 'The minimum price is $5.00.', 'edits keep the minimum price');
select throws_ok(format($$ select public.update_listing(%L, %L, 'ab', '', 5500, 'kitchen') $$, :'alice', :'fridge'),
  '22023', null, 'edits keep the title length');

-- An accepted offer locks the price and blocks removal; the title can still be fixed.
select tests.authenticate_as(:'bob');
select public.open_thread(:'fridge') as t1 \gset
select public.make_offer(:'t1', 5500) as o1 \gset
select tests.authenticate_as(:'alice');
select public.accept_offer(:'o1');
select tests.authenticate_as_service();
select throws_ok(format($$ select public.update_listing(%L, %L, 'Big fridge', 'Cold', 4000, 'kitchen') $$, :'alice', :'fridge'),
  '22023', 'An offer is accepted, so the price is locked until the trade completes or is cancelled.',
  'the price is locked while an offer is accepted');
select lives_ok(format($$ select public.update_listing(%L, %L, 'Big mini fridge', 'Cold', 5500, 'kitchen') $$, :'alice', :'fridge'),
  'the title can still be fixed while an offer is accepted');
select tests.authenticate_as(:'alice');
select throws_ok(format('select public.remove_listing(%L)', :'fridge'), '22023', 'An offer is accepted. Cancel the trade in the chat first.',
  'a listing with an accepted offer cannot be removed');
select public.cancel_offer(:'o1');

-- ===== Remove =====
select tests.authenticate_as(:'carol');
select public.make_offer(public.open_thread(:'fridge'), 5000) as o2 \gset
select throws_ok(format('select public.remove_listing(%L)', :'fridge'), 'P0002', null, 'nobody else can remove the listing');
select tests.authenticate_as_anon();
select throws_ok(format('select public.remove_listing(%L)', :'fridge'), '42501', null, 'anon cannot remove a listing');
select tests.authenticate_as(:'alice');
select lives_ok(format('select public.remove_listing(%L)', :'fridge'), 'the seller removes the listing');
select lives_ok(format('select public.remove_listing(%L)', :'fridge'), 'removing twice is fine');
reset role;
select is((select status from public.listings where id = :'fridge'), 'removed', 'the listing is removed');
select is((select state from public.offers where id = :'o2'), 'declined', 'its pending offers are declined');
select is((select body from public.messages where offer_id = :'o2' and event = 'declined'), 'Declined: the seller took this listing down',
  'the buyer is told why');
select tests.authenticate_as_service();
select throws_ok(format($$ select public.update_listing(%L, %L, 'Back again', '', 5500, 'kitchen') $$, :'alice', :'fridge'),
  '22023', 'Sold or removed listings can''t be edited.', 'a removed listing cannot be edited');

-- ===== Block -> ended event; unblock =====
select tests.authenticate_as(:'bob');
select public.open_thread(:'lamp') as t_lamp \gset
select tests.authenticate_as(:'alice');
select public.block_user(:'bob');
select tests.authenticate_as(:'bob');
select results_eq(format('select event, sender_id is null from public.messages where thread_id = %L and event = %L', :'t_lamp', 'ended'),
  $$ values ('ended'::text, true) $$, 'the blocked side gets a live "ended" event (no sender, so it doesn''t say who)');
select throws_ok(format('select public.unblock_user(%L)', :'alice'), 'P0002', null, 'the blocked person cannot unblock');
select tests.authenticate_as(:'carol');
select throws_ok(format('select public.unblock_user(%L)', :'bob'), 'P0002', null, 'a third member cannot remove someone else''s block');
select tests.authenticate_as(:'alice');
select lives_ok(format('select public.unblock_user(%L)', :'bob'), 'the blocker can unblock');
reset role;
select is((select count(*)::int from public.blocks), 0, 'the block is gone');
select ok((select closed_at is not null from public.threads where id = :'t_lamp'), 'unblocking reopens nothing by itself');
select tests.authenticate_as(:'bob');
select is((select count(*)::int from public.listings where id = :'lamp'), 1, 'the seller''s listings show again');
select is(public.open_thread(:'lamp'), :'t_lamp'::uuid, 'messaging from the listing again reuses the thread');
reset role;
select ok((select closed_at is null from public.threads where id = :'t_lamp'), 'and that explicit step reopens it');

-- ===== Read receipts =====
select tests.authenticate_as(:'bob');
select public.mark_thread_read(:'t_lamp');
select tests.authenticate_as(:'carol');
select public.mark_thread_read(:'t_lamp');
reset role;
select results_eq(format('select buyer_read_at is not null, seller_read_at is null from public.threads where id = %L', :'t_lamp'),
  $$ values (true, true) $$, 'each party only stamps their own receipt; a third member stamps nothing');
select tests.authenticate_as(:'carol');
select is((select count(*)::int from public.threads where id = :'t_lamp'), 0, 'a third member cannot read anyone''s receipts');
select tests.authenticate_as_anon();
select throws_ok(format('select public.mark_thread_read(%L)', :'t_lamp'), '42501', null, 'anon cannot mark a thread read');
select tests.authenticate_as(:'alice');
select ok((select buyer_read_at is not null from public.threads where id = :'t_lamp'), 'the other party sees the receipt');

-- ===== Admin queue: filters and paging =====
reset role;
-- 230 member reports on distinct messages (one open report per target is the dedupe rule).
with m as (
  insert into public.messages (thread_id, sender_id, body)
  select :'t_lamp', :'alice', 'msg ' || i from generate_series(1, 230) i
  returning id
)
insert into public.reports (reporter_id, message_id, listing_id, reported_user_id, reason, status)
select :'bob', m.id, :'lamp', :'alice', (array['scam', 'harassment', 'other'])[1 + (m.id % 3)::int],
       case when m.id % 4 = 0 then 'dismissed' else 'open' end
from m;
insert into public.reports (source, reported_user_id, reason, quoted) values ('moderation', :'bob', 'moderation', 'held');
select tests.authenticate_as(:'bob');
select throws_ok('select * from public.admin_reports()', '42501', null, 'a member cannot read the queue');
select tests.authenticate_as(:'dave');
select is((select count(*)::int from public.admin_reports(p_limit => 500)), 200, 'a page is capped at 200');
select min(id) as page1_last from public.admin_reports(p_limit => 200) \gset
select is((select count(*)::int from public.admin_reports(p_before => :page1_last, p_limit => 200)), 31, 'paging past 200 reaches the rest');
select ok((select bool_and(status = 'open') and count(*) > 0 from public.admin_reports(p_status => 'open', p_limit => 200)), 'filter by status (open)');
select results_eq($$ select distinct source from public.admin_reports(p_source => 'moderation') $$, $$ values ('moderation'::text) $$,
  'filter by source');
select ok((select bool_and(reason = 'harassment') and count(*) > 0 from public.admin_reports(p_reason => 'harassment', p_limit => 200)), 'filter by reason');

select * from finish();
rollback;
