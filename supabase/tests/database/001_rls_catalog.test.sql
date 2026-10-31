-- Guardrail: no table or view in `public` can ship without row level security.
begin;
select plan(10);

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

-- Functions run as invoker are still callable through the API; anon gets none of them.
select is_empty(
  $$ select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute') $$,
  'anon can execute no public function'
);

-- Buckets: none public, and each one has a read policy that names it.
select is_empty($$ select id from storage.buckets where public $$, 'no storage bucket is public');
select is_empty(
  $$ select b.id from storage.buckets b
     where not exists (select 1 from pg_policies p
                       where p.schemaname = 'storage' and p.tablename = 'objects'
                         and p.qual like '%' || quote_literal(b.id) || '%') $$,
  'every storage bucket has a policy scoped to it'
);

-- postgres_changes delivers a row to every subscriber who passes its SELECT policy, so a
-- published table without RLS or a select policy would broadcast to everyone.
select is_empty(
  $$ select pt.tablename from pg_publication_tables pt join pg_class c on c.oid = (pt.schemaname || '.' || pt.tablename)::regclass
     where pt.pubname = 'supabase_realtime'
       and (not c.relrowsecurity
            or not exists (select 1 from pg_policy p where p.polrelid = c.oid and p.polcmd in ('r', '*'))) $$,
  'every table published to realtime has RLS and a select policy'
);

create table public.rls_probe (id int);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.rls_probe'::regclass),
  'event trigger turns RLS on for a newly created table'
);

select * from finish();
rollback;
