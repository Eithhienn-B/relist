-- Reports and the admin queue. Bob buys from Alice, Carol is a third member, Dave is an admin.
begin;
select plan(33);

select id as indy from public.campuses where name = 'Indianapolis' \gset
select tests.create_user('alice@purdue.edu') as alice \gset
select tests.create_user('bob@purdue.edu') as bob \gset
select tests.create_user('carol@purdue.edu') as carol \gset
select tests.create_user('dave@purdue.edu') as dave \gset
insert into public.memberships (user_id, email, school_id, campus_id, grad_season, grad_year, is_18_plus)
select u, e, 243780, :indy, 'spring', 2029, true
from (values (:'alice'::uuid, 'alice@purdue.edu'), (:'bob'::uuid, 'bob@purdue.edu'),
             (:'carol'::uuid, 'carol@purdue.edu'), (:'dave'::uuid, 'dave@purdue.edu')) v(u, e);
insert into private.admins (user_id) values (:'dave');

insert into public.listings (seller_id, school_id, campus_id, title, price_cents, category)
values (:'alice', 243780, :indy, 'Mini fridge', 6000, 'kitchen') returning id as fridge \gset
insert into public.threads (listing_id, buyer_id, seller_id) values (:'fridge', :'bob', :'alice') returning id as t1 \gset
insert into public.messages (thread_id, sender_id, body) values (:'t1', :'alice', 'Pay me on Zelle first') returning id as m_scam \gset
insert into public.messages (thread_id, sender_id, body) values (:'t1', :'bob', 'ok') returning id as m_bob \gset
insert into public.messages (thread_id, sender_id, body, held) values (:'t1', :'alice', 'held text', true) returning id as m_held \gset

-- Member reports: the reporter is always the caller
select tests.authenticate_as(:'bob');
select public.report('scam', 'asked for Zelle', p_message_id => :m_scam) as r1 \gset
select is(public.report('scam', 'again', p_message_id => :m_scam), :r1::bigint,
  'reporting the same message twice returns the open report (no queue flooding)');
select tests.authenticate_as(:'carol');
select throws_ok(format($$ select public.report('scam', p_message_id => %s) $$, :m_scam), 'P0002', null,
  'a third member cannot report a message in someone else''s thread');
select throws_ok(
  format($$ insert into public.reports (reporter_id, message_id, reason) values (%L, %s, 'scam') $$, :'bob', :m_scam),
  '42501', null, 'a member cannot insert a report directly (no reporting as someone else)');
select ok(not exists (select 1 from pg_proc where proname = 'report' and 'p_reporter' = any(proargnames)),
  'report() has no reporter parameter');
select is_empty('select 1 from public.reports', 'a member cannot see other people''s reports');
select throws_ok(format($$ select public.report('other', p_user_id => %L) $$, :'alice'), 'P0002', null,
  'a member cannot report a user they have never talked to');
select lives_ok(format($$ select public.report('fake_listing', p_listing_id => %L) $$, :'fridge'),
  'any member can report a listing they can see');
select tests.authenticate_as(:'bob');
select throws_ok(format($$ select public.report('scam', p_message_id => %s) $$, :m_bob), 'P0002', null,
  'you cannot report your own message');
select throws_ok(format($$ select public.report('scam', p_message_id => %s) $$, :m_held), 'P0002', null,
  'you cannot report a held message you cannot see');
select throws_ok(format($$ select public.report('moderation', p_user_id => %L) $$, :'alice'), '22023', null,
  'members cannot file moderation reports');
select throws_ok(format($$ select public.report('scam', p_user_id => %L, p_listing_id => %L) $$, :'alice', :'fridge'), '22023', null,
  'a report names exactly one target');
select results_eq('select reason, note from public.reports', $$ values ('scam', 'asked for Zelle') $$,
  'the reporter sees their own report');
select throws_ok('select flags from public.reports', '42501', null, 'members cannot read moderation flags');
reset role;
select results_eq(format('select reporter_id, quoted, reported_user_id, listing_id from public.reports where id = %s', :r1),
  format($$ values (%L::uuid, 'Pay me on Zelle first', %L::uuid, %L::uuid) $$, :'bob', :'alice', :'fridge'),
  'a message report snapshots the quote server-side and targets the sender and listing');
update public.config set reports_per_day = 1 where school_id is null;
select tests.authenticate_as(:'bob');
select throws_ok(format($$ select public.report('harassment', p_user_id => %L) $$, :'alice'), '54000', null,
  'reports are rate limited per user');
reset role;
update public.config set reports_per_day = 20 where school_id is null;

-- Admin functions refuse non-admins
select tests.authenticate_as(:'bob');
select throws_ok('select * from public.admin_reports()', '42501', null, 'a member cannot read the report queue');
select throws_ok('select * from public.admin_stats()', '42501', null, 'a member cannot read admin stats');
select throws_ok(format($$ select public.admin_resolve_report(%s, 'suspend_user') $$, :r1), '42501', null,
  'a member cannot resolve a report');
select throws_ok('select 1 from private.admins', '42501', null, 'a member cannot read or write the admin list');
select tests.authenticate_as_anon();
select throws_ok('select * from public.admin_reports()', '42501', null, 'anon cannot read the report queue');
select tests.authenticate_as_service();
select throws_ok('select * from public.admin_reports()', '42501', null, 'the secret key alone is not an admin');

-- Admin
select tests.authenticate_as(:'dave');
select results_eq(format('select quoted, reporter_email from public.admin_reports() where id = %s', :r1),
  $$ values ('Pay me on Zelle first', 'bob@purdue.edu') $$, 'an admin sees the report with its quoted message');
select results_eq('select open_reports from public.admin_stats()', 'values (2::bigint)', 'an admin sees open report counts');
select lives_ok(format($$ select public.admin_resolve_report(%s, 'hide_listing') $$, :r1), 'an admin hides the listing');
reset role;
select is((select status from public.listings where id = :'fridge'), 'removed', 'hiding sets the listing to removed');
select is((select status from public.reports where id = :r1), 'actioned', 'the report is marked actioned');
select id as r2 from public.reports where reason = 'fake_listing' \gset
select tests.authenticate_as(:'dave');
select lives_ok(format($$ select public.admin_resolve_report(%s, 'suspend_user') $$, :r2),
  'an admin suspends the user from another open report');
select throws_ok(format($$ select public.admin_resolve_report(%s, 'dismiss') $$, :r1), '22023', null,
  'a resolved report cannot be resolved again');
reset role;
select ok((select banned_until between now() + interval '50 years' and 'infinity'::timestamptz - interval '1 day'
           from auth.users where id = :'alice'),
  'suspension is a finite far-future ban (Supabase Auth fails on infinity)');
select tests.authenticate_as(:'dave');
select tests.authenticate_as(:'alice');
select throws_ok(format('select public.can_send_message(%L)', :'t1'), '42501', 'Your account is suspended.',
  'a suspended user cannot send');
select throws_ok(format('select public.open_thread(%L)', :'fridge'), '42501', 'Your account is suspended.',
  'a suspended user cannot open threads');
select tests.authenticate_as_service();
select throws_ok(format($$ select public.send_message(%L, %L, 'hi', '{}', false) $$, :'alice', :'t1'),
  '42501', 'Your account is suspended.', 'the server send path refuses a suspended sender');
reset role;
select throws_ok(
  format($$ insert into public.listings (seller_id, school_id, campus_id, title, price_cents, category)
            values (%L, 243780, %s, 'New spam', 1500, 'other') $$, :'alice', :indy),
  '42501', 'Your account is suspended.', 'a suspended user cannot create listings on any path');

select * from finish();
rollback;
