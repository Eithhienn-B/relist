-- Privacy suite, tenancy tables. Grows with every table that holds private rows.
begin;
select plan(13);

select tests.create_user('alice@purdue.edu') as alice \gset
select tests.create_user('bob@purdue.edu') as bob \gset

-- Seed memberships directly as the owner (clients can't insert them).
insert into public.memberships (user_id, email, school_id, grad_season, grad_year, is_18_plus) values
  (:'alice', 'alice@purdue.edu', 243780, 'spring', 2029, true),
  (:'bob', 'bob@purdue.edu', 243780, 'fall', 2028, true);

-- Signed in as Alice
select tests.authenticate_as(:'alice');

select results_eq(
  'select user_id from public.memberships',
  format('values (%L::uuid)', :'alice'),
  'a user sees only their own membership'
);

select throws_ok(
  format($$ insert into public.memberships (user_id, email, grad_season, grad_year, is_18_plus)
            values (%L, 'x@purdue.edu', 'fall', 2028, true) $$, :'bob'),
  '42501', null, 'a user cannot insert a membership for someone else'
);

select throws_ok(
  $$ update public.memberships set school_id = 151324 $$,
  '42501', null, 'a user cannot update memberships, even their own'
);

select throws_ok(
  $$ delete from public.memberships $$,
  '42501', null, 'a user cannot delete memberships'
);

select throws_ok(
  $$ update public.config set fee_bps = 0 $$,
  '42501', null, 'a user cannot change fee config'
);

select throws_ok(
  $$ insert into public.school_domains (domain, school_id) values ('evil.edu', 243780) $$,
  '42501', null, 'a user cannot add a school domain'
);

select isnt_empty('select 1 from public.campuses', 'signed-in users can read campuses');
select isnt_empty('select 1 from public.config', 'signed-in users can read config');

-- Anonymous
select tests.authenticate_as_anon();

select throws_ok('select * from public.memberships', '42501', null, 'anon cannot query memberships at all');
select throws_ok('select * from public.schools', '42501', null, 'anon cannot query schools');
select throws_ok('select * from public.campuses', '42501', null, 'anon cannot query campuses');
select throws_ok('select * from public.school_domains', '42501', null, 'anon cannot query school domains');
select throws_ok('select * from public.config', '42501', null, 'anon cannot query config');

select * from finish();
rollback;
