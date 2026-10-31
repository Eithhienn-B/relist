-- Guardrail: no table or view in `public` can ship without row level security.
begin;
select plan(6);

select is_empty(
  $$ select table_name, privilege_type from information_schema.role_table_grants
     where table_schema = 'public' and grantee = 'anon' $$,
  'anon has no privileges on any public table'
);

-- security definer skips RLS, so each one must pin search_path and be closed to anon.
select is_empty(
  $$ select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prosecdef
       and (not coalesce(p.proconfig::text like '%search_path=%', false)
            or has_function_privilege('anon', p.oid, 'execute')) $$,
  'every public security definer function pins search_path and denies anon'
);

select is_empty(
  $$ select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relrowsecurity $$,
  'every public table has RLS enabled'
);

select is_empty(
  $$ select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind in ('r', 'p')
       and not exists (select 1 from pg_policy p where p.polrelid = c.oid) $$,
  'every public table has at least one policy'
);

-- Views run as their owner and skip RLS unless security_invoker is set.
select is_empty(
  $$ select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind in ('v', 'm')
       and not coalesce('security_invoker=true' = any(c.reloptions), false) $$,
  'every public view is security_invoker'
);

create table public.rls_probe (id int);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.rls_probe'::regclass),
  'event trigger turns RLS on for a newly created table'
);

select * from finish();
rollback;
