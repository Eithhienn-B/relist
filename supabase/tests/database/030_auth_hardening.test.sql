-- Review fixes: OTP-only accounts, .edu-only email changes, approved domains, one account per mailbox.
begin;
select plan(8);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'pw@purdue.edu', crypt('attacker-pass', gen_salt('bf')), now(), now(), now());
select is((select encrypted_password from auth.users where email = 'pw@purdue.edu'), '', 'passwords are stripped on sign-up (OTP only)');

update auth.users set encrypted_password = 'x' where email = 'pw@purdue.edu';
select is((select encrypted_password from auth.users where email = 'pw@purdue.edu'), '', 'passwords cannot be set later');

select throws_ok($$ update auth.users set email = 'pw@gmail.com' where email = 'pw@purdue.edu' $$,
  '42501', null, 'email cannot change to a non-.edu address');
select lives_ok($$ update auth.users set email = 'pw2@purdue.edu' where email = 'pw@purdue.edu' $$,
  'email can change to another .edu address');

-- Unapproved domain maps to no school
insert into public.school_domains (domain, school_id) values ('pending.edu', 243780);
select tests.create_user('hal@pending.edu') as hal \gset
select tests.authenticate_as(:'hal');
select public.create_membership('fall', 2028, true);
select is((select school_id from public.memberships), null, 'an unapproved domain does not map to a school');
reset role;

-- One account per mailbox
select tests.create_user('ivy+1@purdue.edu') as ivy1 \gset
select tests.create_user('ivy+2@purdue.edu') as ivy2 \gset
select tests.authenticate_as(:'ivy1');
select lives_ok($$ select public.create_membership('fall', 2028, true) $$, 'first plus-alias onboards');
select tests.authenticate_as(:'ivy2');
select throws_ok($$ select public.create_membership('fall', 2028, true) $$, '23505', null, 'a second plus-alias of the same mailbox is rejected');

-- Signed-in users can't reach private helpers
select throws_ok($$ select private.hook_before_user_created('{}') $$, '42501', null, 'signed-in users cannot call private functions');

select * from finish();
rollback;
