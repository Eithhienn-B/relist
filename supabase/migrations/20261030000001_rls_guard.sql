-- Helpers that must never be reachable through the Data API live in `private`.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

-- Every new table in `public` gets RLS on the moment it is created,
-- so a table can't ship without RLS even if a migration forgets the line.
create or replace function private.enable_rls_on_new_table()
returns event_trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  obj record;
begin
  for obj in
    select * from pg_event_trigger_ddl_commands()
    where object_type = 'table' and schema_name = 'public'
  loop
    execute format('alter table %s enable row level security', obj.object_identity);
  end loop;
end;
$$;

create event trigger enable_rls_on_new_table
  on ddl_command_end
  when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
  execute function private.enable_rls_on_new_table();
