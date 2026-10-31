-- Guardrail: no table or view in `public` can ship without row level security.
begin;
select plan(4);

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
