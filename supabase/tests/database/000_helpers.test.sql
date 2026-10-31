-- Shared helpers for every test file. Runs first (files run in name order) and is NOT rolled back,
-- so later files can call tests.*. The `tests` schema exists only in test databases, never in migrations.
create extension if not exists pgtap with schema extensions;
create schema if not exists tests;
grant usage on schema tests to anon, authenticated;

-- Creates a confirmed auth user (as if they finished the OTP) and returns its id.
create or replace function tests.create_user(p_email text, p_confirmed boolean default true)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := gen_random_uuid();
begin
  insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values (v_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', p_email,
          case when p_confirmed then now() end, '{"provider":"email","providers":["email"]}', '{}', now(), now());
  return v_id;
end;
$$;

-- Switches the session to a signed-in user, the way PostgREST does for a request with their JWT.
create or replace function tests.authenticate_as(p_user_id uuid)
returns void
language plpgsql
set search_path = ''
as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user_id, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

create or replace function tests.authenticate_as_anon()
returns void
language plpgsql
set search_path = ''
as $$
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('role', 'anon', true);
end;
$$;

-- The server's secret-key client: PostgREST runs it as service_role with no user (auth.uid() is null).
create or replace function tests.authenticate_as_service()
returns void
language plpgsql
set search_path = ''
as $$
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('role', 'service_role', true);
end;
$$;

grant usage on schema tests to service_role;
grant execute on all functions in schema tests to anon, authenticated, service_role;

begin;
select plan(1);
select has_function('tests', 'authenticate_as', array['uuid'], 'test helpers are installed');
select * from finish();
rollback;
