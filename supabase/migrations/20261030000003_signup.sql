-- One rule for "is this a student address", shared by the auth hook and create_membership().
create or replace function private.is_edu_email(p_email text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select coalesce(lower(p_email) ~ '^[^@\s]+@([a-z0-9-]+\.)+edu$', false);
$$;

-- Before User Created hook: only .edu addresses can create an account.
create or replace function private.hook_before_user_created(event jsonb)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
begin
  if private.is_edu_email(event -> 'user' ->> 'email') then
    return '{}'::jsonb;
  end if;
  return jsonb_build_object('error', jsonb_build_object(
    'http_code', 403,
    'message', 'ReList is for students. Sign up with your school (.edu) email.'
  ));
end;
$$;

grant usage on schema private to supabase_auth_admin;
grant execute on function private.hook_before_user_created(jsonb), private.is_edu_email(text) to supabase_auth_admin;

-- Onboarding: turns a verified .edu account into a membership.
-- School and campus come from the server's domain lookup, never from the client.
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

  select d.school_id into v_school_id from public.school_domains d where d.domain = split_part(v_email, '@', 2);
  select c.id into v_campus_id from public.campuses c where c.school_id = v_school_id and c.is_default;

  insert into public.memberships (user_id, email, school_id, campus_id, grad_season, grad_year, is_18_plus)
  values ((select auth.uid()), v_email, v_school_id, v_campus_id, p_grad_season, p_grad_year, p_is_18_plus)
  returning * into v_membership;

  return v_membership;
end;
$$;

revoke execute on function public.create_membership(text, int, boolean) from public, anon;
grant execute on function public.create_membership(text, int, boolean) to authenticated;
