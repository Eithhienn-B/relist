-- Review fixes (10/30/2026).

-- 1. OTP-only accounts. A password sign-up for someone else's address could get a session
--    (and a "confirmed" email) without proving inbox control. Passwords are stripped, so the
--    only way in is a code sent to the mailbox. Email changes must stay on .edu.
create or replace function private.guard_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.encrypted_password := '';
  if tg_op = 'UPDATE' and new.email is distinct from old.email and not private.is_edu_email(new.email) then
    raise exception 'ReList accounts must keep a school (.edu) email' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger guard_auth_user
  before insert or update of encrypted_password, email on auth.users
  for each row execute function private.guard_auth_user();

-- 2. Only approved domains map to a school.
create or replace function public.create_membership(p_grad_season text, p_grad_year int, p_is_18_plus boolean)
returns public.memberships
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text;
  v_school_id bigint;
  v_campus_id bigint;
  v_membership public.memberships;
begin
  select lower(u.email) into v_email
  from auth.users u
  where u.id = (select auth.uid()) and u.email_confirmed_at is not null;

  if v_email is null then
    raise exception 'Verify your email first' using errcode = '42501';
  end if;
  if not private.is_edu_email(v_email) then
    raise exception 'A school (.edu) email is required' using errcode = '42501';
  end if;
  if p_is_18_plus is not true then
    raise exception 'You must be 18 or older to use ReList' using errcode = '22023';
  end if;

  select d.school_id into v_school_id
  from public.school_domains d
  where d.domain = split_part(v_email, '@', 2) and d.approved_at is not null;
  select c.id into v_campus_id from public.campuses c where c.school_id = v_school_id and c.is_default;

  insert into public.memberships (user_id, email, school_id, campus_id, grad_season, grad_year, is_18_plus)
  values ((select auth.uid()), v_email, v_school_id, v_campus_id, p_grad_season, p_grad_year, p_is_18_plus)
  returning * into v_membership;

  return v_membership;
end;
$$;

-- 3. One account per mailbox: a+1@purdue.edu and a+2@purdue.edu are the same person (gem-farming sybils).
create unique index memberships_normalized_email on public.memberships
  ((regexp_replace(split_part(email, '@', 1), '\+.*$', '') || '@' || split_part(email, '@', 2)));

-- 4. Tight grants: anon gets nothing in public, now and for tables created later.
revoke all on public.schools, public.campuses, public.school_domains, public.memberships, public.config
  from anon, authenticated;
grant select on public.schools, public.campuses, public.school_domains, public.memberships, public.config
  to authenticated;
alter default privileges for role postgres in schema public revoke all on tables from anon;
alter default privileges for role postgres in schema public revoke all on sequences from anon;
alter default privileges for role postgres in schema public revoke execute on functions from anon, public;
