-- Privacy suite, chat: threads, messages, blocks, the send path and the realtime publication.
-- Alice sells, Bob buys, Carol is a third member, Mallory never finished sign-up.
begin;
select plan(45);

select id as indy from public.campuses where name = 'Indianapolis' \gset
select tests.create_user('alice@purdue.edu') as alice \gset
select tests.create_user('bob@purdue.edu') as bob \gset
select tests.create_user('carol@purdue.edu') as carol \gset
select tests.create_user('mallory@purdue.edu') as mallory \gset
insert into public.memberships (user_id, email, school_id, campus_id, grad_season, grad_year, is_18_plus) values
  (:'alice', 'alice@purdue.edu', 243780, :indy, 'spring', 2029, true),
  (:'bob', 'bob@purdue.edu', 243780, :indy, 'spring', 2029, true),
  (:'carol', 'carol@purdue.edu', 243780, :indy, 'spring', 2029, true);

insert into public.listings (seller_id, school_id, campus_id, title, price_cents, category)
values (:'alice', 243780, :indy, 'Mini fridge', 6000, 'kitchen') returning id as fridge \gset
insert into public.listings (seller_id, school_id, campus_id, title, price_cents, category)
values (:'alice', 243780, :indy, 'Desk chair', 3000, 'furniture') returning id as chair \gset
insert into public.listings (seller_id, school_id, campus_id, title, price_cents, category, status)
values (:'alice', 243780, :indy, 'Old rug', 1500, 'decor', 'removed') returning id as rug \gset
insert into public.listings (seller_id, school_id, campus_id, title, price_cents, category)
values (:'bob', 243780, :indy, 'Calc textbook', 4000, 'textbooks') returning id as book \gset
insert into public.listings (seller_id, school_id, campus_id, title, price_cents, category, status)
values (:'alice', 243780, :indy, 'Sold lamp', 1500, 'decor', 'sold') returning id as sold \gset

-- Opening threads
select tests.authenticate_as(:'bob');
select public.open_thread(:'fridge') as t1 \gset
select is(public.open_thread(:'fridge'), :'t1'::uuid, 'opening a thread twice returns the same thread');
select throws_ok(format('select public.open_thread(%L)', :'rug'), 'P0002', null, 'nobody can open a thread on a removed listing');
select throws_ok(format('select public.open_thread(%L)', :'sold'), 'P0002', null,
  'a new thread needs an active listing (no probing sold or pending ones)');
reset role;
update public.listings set status = 'pending' where id = :'fridge';
select tests.authenticate_as(:'bob');
select is(public.open_thread(:'fridge'), :'t1'::uuid, 'an existing thread survives its listing going pending');
reset role;
update public.listings set status = 'active' where id = :'fridge';
select tests.authenticate_as(:'bob');
select tests.authenticate_as(:'alice');
select throws_ok(format('select public.open_thread(%L)', :'fridge'), '22023', null, 'a seller cannot open a thread on their own listing');
select tests.authenticate_as(:'mallory');
select throws_ok(format('select public.open_thread(%L)', :'fridge'), '42501', null, 'an account without a membership cannot open a thread');
select tests.authenticate_as_anon();
select throws_ok(format('select public.open_thread(%L)', :'fridge'), '42501', null, 'anon cannot open a thread');
select tests.authenticate_as(:'bob');
select throws_ok(
  format($$ insert into public.threads (listing_id, buyer_id, seller_id) values (%L, %L, %L) $$, :'chair', :'carol', :'alice'),
  '42501', null, 'a member cannot insert a thread directly (or open one for someone else)');

-- Sending: only the server (secret key) can call send_message, and it re-checks the sender.
select throws_ok(
  format($$ select public.send_message(%L, %L, 'hi', '{}', false) $$, :'bob', :'t1'),
  '42501', null, 'a member cannot call send_message (no posting as someone else)');
select throws_ok(
  format($$ insert into public.messages (thread_id, sender_id, body) values (%L, %L, 'hi') $$, :'t1', :'bob'),
  '42501', null, 'a member cannot insert messages directly');
select tests.authenticate_as_service();
select lives_ok(format($$ select public.send_message(%L, %L, 'Is the fridge still available?', '{}', false) $$, :'bob', :'t1'),
  'the server can send for a party to the thread');
select (public.send_message(:'alice', :'t1', 'Yes! Venmo me @alice-f', '{}', true)).id as m_alice \gset
select (public.send_message(:'alice', :'t1', 'held words', '{harassment}', false)).id as m_held \gset
select throws_ok(format($$ select public.send_message(%L, %L, 'let me in', '{}', false) $$, :'carol', :'t1'),
  '42501', 'Conversation not found', 'the server cannot post as a third member into someone else''s thread');
select throws_ok(format($$ select public.send_message(%L, %L, 'hi', '{}', false) $$, :'mallory', :'t1'),
  '42501', null, 'the server cannot post as a non-member');
select throws_ok(format($$ select public.send_message(%L, %L, '   ', '{}', false) $$, :'bob', :'t1'),
  '22023', null, 'blank messages are refused');
reset role;
select is((select count(*)::int from public.reports where source = 'moderation' and message_id = :m_held),
  1, 'a flagged message auto-files a moderation report');

-- Reading
select tests.authenticate_as(:'bob');
select results_eq('select body from public.messages order by id',
  $$ values ('Is the fridge still available?'), ('Yes! Venmo me @alice-f') $$,
  'the recipient sees the thread but not the held message');
select throws_ok(format('update public.messages set body = %L', 'edited'), '42501', null, 'messages cannot be edited (append-only)');
select throws_ok('delete from public.messages', '42501', null, 'messages cannot be deleted (append-only)');
select tests.authenticate_as(:'alice');
select is((select count(*)::int from public.messages where held), 1, 'the sender sees their own held message');
select throws_ok(format($$ update public.threads set closed_at = null where id = %L $$, :'t1'), '42501', null,
  'a party cannot update their thread');
select tests.authenticate_as(:'carol');
select is_empty('select 1 from public.threads', 'a third member sees no threads');
select is_empty('select 1 from public.messages', 'a third member sees no messages');
select throws_ok(format('select public.can_send_message(%L)', :'t1'), '42501', null, 'a third member cannot pass the send check');
select tests.authenticate_as_anon();
select throws_ok('select 1 from public.messages', '42501', null, 'anon cannot read messages');
select throws_ok('select 1 from public.threads', '42501', null, 'anon cannot read threads');
reset role;

-- Realtime: postgres_changes on messages is filtered by the SELECT policy above, per subscriber.
select ok(exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'messages'),
  'messages are published to realtime');
select is_empty(
  $$ select tablename from pg_publication_tables where pubname = 'supabase_realtime'
     and tablename not in ('messages', 'threads') $$,
  'only messages and threads (read receipts) are published to realtime');

-- Rate limits (per thread per minute, per user per hour)
select tests.authenticate_as(:'carol');
select public.open_thread(:'chair') as t2 \gset
reset role;
insert into public.messages (thread_id, sender_id, body) select :'t2', :'carol', 'spam' from generate_series(1, 10);
select tests.authenticate_as_service();
select throws_ok(format($$ select public.send_message(%L, %L, 'one more', '{}', false) $$, :'carol', :'t2'),
  '54000', 'Slow down a little. Try again in a minute.', 'the per-thread limit stops the 11th message in a minute');
reset role;
update public.messages set created_at = now() - interval '5 minutes' where thread_id = :'t2';
update public.config set msg_user_per_hour = 10 where school_id is null;
select tests.authenticate_as(:'carol');
select throws_ok(format('select public.can_send_message(%L)', :'t2'),
  '54000', 'You''re sending messages too fast. Try again later.', 'the per-user hourly limit applies to the pre-check too');
reset role;
update public.config set msg_user_per_hour = 120, threads_per_hour = 1 where school_id is null;
select tests.authenticate_as(:'carol');
select throws_ok(format('select public.open_thread(%L)', :'fridge'), '54000', null,
  'opening threads is rate limited per user');
reset role;
update public.config set threads_per_hour = 20 where school_id is null;

-- Blocking ends the thread both ways
select tests.authenticate_as(:'alice');
select throws_ok(format('select public.block_user(%L)', :'alice'), '22023', null, 'you cannot block yourself');
select throws_ok(format('select public.block_user(%L)', :'mallory'), 'P0002', null,
  'you can only block someone you have talked to (no probing for user ids)');
select lives_ok(format('select public.block_user(%L)', :'bob'), 'the seller blocks the buyer');
select throws_ok(format('select public.can_send_message(%L)', :'t1'), '42501', 'This conversation has ended.',
  'the blocker cannot post either');
select tests.authenticate_as(:'bob');
select throws_ok(format('select public.can_send_message(%L)', :'t1'), '42501', 'This conversation has ended.',
  'the blocked user cannot post');
select throws_ok(format('select public.open_thread(%L)', :'chair'), 'P0002', null,
  'the blocked user cannot open a new thread with the blocker');
select is_empty(format('select 1 from public.listings where seller_id = %L', :'alice'),
  'the blocked user no longer sees the blocker''s listings');
select throws_ok(format('delete from public.blocks where blocker_id = %L', :'alice'), '42501', null,
  'the blocked user cannot remove the block');
select is((select count(*)::int from public.messages where thread_id = :'t1' and event is null), 2, 'the thread history stays readable');
select is((select body from public.messages where thread_id = :'t1' and event = 'ended'), 'This conversation has ended.',
  'both sides get a live "ended" event that doesn''t say who blocked');
select tests.authenticate_as(:'alice');
select is_empty(format('select 1 from public.listings where id = %L', :'book'),
  'the blocker no longer sees the blocked user''s listings');
select tests.authenticate_as_service();
select throws_ok(format($$ select public.send_message(%L, %L, 'please', '{}', false) $$, :'bob', :'t1'),
  '42501', 'This conversation has ended.', 'the server send path refuses a blocked thread');
reset role;
update public.threads set closed_at = null where id = :'t1';
select tests.authenticate_as(:'bob');
select throws_ok(format('select public.can_send_message(%L)', :'t1'), '42501', 'This conversation has ended.',
  'the block itself stops posting even if closed_at were cleared');
select tests.authenticate_as(:'carol');
select isnt_empty(format('select 1 from public.listings where id = %L', :'fridge'), 'other members still see the blocker''s listings');
select is_empty('select 1 from public.blocks', 'other members cannot see someone else''s blocks');

select * from finish();
rollback;
