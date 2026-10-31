-- Sign-up gate (auth hook) and onboarding (create_membership).
begin;
select plan(16);

-- Before User Created hook
select is(private.hook_before_user_created('{"user":{"email":"a@purdue.edu"}}'), '{}'::jsonb, 'hook allows purdue.edu');
select is(private.hook_before_user_created('{"user":{"email":"A@Sycamores.IndState.EDU"}}'), '{}'::jsonb, 'hook allows a mixed-case .edu subdomain');
select is(private.hook_before_user_created('{"user":{"email":"a@unknown-college.edu"}}'), '{}'::jsonb, 'hook allows an unknown .edu');
select ok(private.hook_before_user_created('{"user":{"email":"a@gmail.com"}}') ? 'error', 'hook rejects gmail.com');
select ok(private.hook_before_user_created('{"user":{"email":"a@purdue.edu.evil.com"}}') ? 'error', 'hook rejects .edu in the middle of a domain');
select ok(private.hook_before_user_created('{"user":{"email":"a@edu"}}') ? 'error', 'hook rejects bare "edu"');
select ok(private.hook_before_user_created('{"user":{}}') ? 'error', 'hook rejects a missing email');

select tests.create_user('cara@purdue.edu') as cara \gset
select tests.create_user('dev@unknown-college.edu') as dev \gset
select tests.create_user('eve@purdue.edu', false) as eve \gset
select tests.create_user('gina@gmail.com') as gina \gset

-- Purdue student: school and default campus come from the server
select tests.authenticate_as(:'cara');
select throws_ok($$ select public.create_membership('fall', 2029, false) $$, '22023', null, 'onboarding requires the 18+ box');
select lives_ok($$ select public.create_membership('fall', 2029, true) $$, 'purdue.edu student can create a membership');
select results_eq(
  $$ select m.school_id, c.name from public.memberships m join public.campuses c on c.id = m.campus_id $$,
  $$ values (243780::bigint, 'Indianapolis'::text) $$,
  'purdue.edu maps to Purdue, default campus Indianapolis'
);
select throws_ok($$ select public.create_membership('fall', 2029, true) $$, '23505', null, 'a second membership is rejected');

-- Unknown .edu: signs up with no home school
select tests.authenticate_as(:'dev');
select lives_ok($$ select public.create_membership('spring', 2027, true) $$, 'unknown .edu can create a membership');
select results_eq('select school_id, campus_id from public.memberships', 'values (null::bigint, null::bigint)', 'unknown .edu has no home school or campus');

-- Unverified email and non-.edu are rejected even if they reach onboarding
select tests.authenticate_as(:'eve');
select throws_ok($$ select public.create_membership('fall', 2029, true) $$, '42501', null, 'unverified email cannot onboard');
select tests.authenticate_as(:'gina');
select throws_ok($$ select public.create_membership('fall', 2029, true) $$, '42501', null, 'non-.edu account cannot onboard');

select tests.authenticate_as_anon();
select throws_ok($$ select public.create_membership('fall', 2029, true) $$, '42501', null, 'anon cannot call create_membership');

select * from finish();
rollback;
