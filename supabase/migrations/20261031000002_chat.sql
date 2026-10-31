-- M2: chat, blocks, reports, admin queue.
-- Clients only SELECT. Writes go through security definer functions below; the sender of a
-- message and the reporter of a report always come from auth.uid() or the server, never a parameter
-- a member can set.

alter table public.config
  add column msg_user_per_hour int not null default 120 check (msg_user_per_hour > 0),
  add column msg_thread_per_minute int not null default 10 check (msg_thread_per_minute > 0),
  add column reports_per_day int not null default 20 check (reports_per_day > 0),
  add column threads_per_hour int not null default 20 check (threads_per_hour > 0);

-- One thread per (listing, buyer). seller_id is copied from the listing so policies stay one join deep.
create table public.threads (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings on delete cascade,
  buyer_id uuid not null references auth.users on delete cascade,
  seller_id uuid not null references auth.users on delete cascade,
  created_at timestamptz not null default now(),
  last_message_at timestamptz,
  closed_at timestamptz, -- set when either side blocks the other; nobody can post after this
  unique (listing_id, buyer_id),
  check (buyer_id <> seller_id)
);
create index threads_buyer_idx on public.threads (buyer_id, last_message_at desc nulls last);
create index threads_seller_idx on public.threads (seller_id, last_message_at desc nulls last);

-- Append-only for clients (no update or delete grant) so reports can quote them.
create table public.messages (
  id bigint generated always as identity primary key,
  thread_id uuid not null references public.threads on delete cascade,
  sender_id uuid not null references auth.users on delete cascade,
  body text not null check (char_length(body) between 1 and 2000),
  held boolean not null default false, -- flagged by moderation: the sender sees it, the recipient doesn't
  nudge boolean not null default false, -- off-platform contact or payment detected (src/lib/nudge.ts)
  created_at timestamptz not null default now()
);
create index messages_thread_idx on public.messages (thread_id, created_at);
create index messages_sender_idx on public.messages (sender_id, created_at desc);
-- admin_stats counts
create index messages_nudge_idx on public.messages (created_at) where nudge;
create index messages_held_idx on public.messages (created_at) where held;

create table public.blocks (
  blocker_id uuid not null references auth.users on delete cascade,
  blocked_id uuid not null references auth.users on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
create index blocks_blocked_idx on public.blocks (blocked_id, blocker_id);

create table public.reports (
  id bigint generated always as identity primary key,
  reporter_id uuid references auth.users on delete set null, -- null when filed by moderation
  source text not null default 'member' check (source in ('member', 'moderation')),
  message_id bigint references public.messages on delete set null,
  listing_id uuid references public.listings on delete set null,
  reported_user_id uuid references auth.users on delete set null,
  reason text not null check (reason in
    ('scam', 'off_platform_payment', 'harassment', 'prohibited_item', 'fake_listing', 'unsafe_meetup', 'other', 'moderation')),
  note text check (char_length(note) <= 500),
  quoted text, -- snapshot of the reported message, taken server-side
  flags text[] not null default '{}', -- moderation categories, admin-only
  status text not null default 'open' check (status in ('open', 'dismissed', 'actioned')),
  resolved_by uuid references auth.users on delete set null,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  -- Member reports keep their row if the reporter later deletes their account (reporter_id -> null).
  check ((source = 'moderation' and reporter_id is null and reason = 'moderation')
         or (source = 'member' and reason <> 'moderation'))
);
create index reports_queue_idx on public.reports (status, created_at desc);
create index reports_reporter_idx on public.reports (reporter_id, created_at desc);
create index reports_message_idx on public.reports (message_id);
create index reports_listing_idx on public.reports (listing_id);
create index reports_user_idx on public.reports (reported_user_id);
create index reports_resolved_by_idx on public.reports (resolved_by);
-- One open report per reporter and target, so one member can't bury the queue with repeats.
create unique index reports_open_dedupe_idx on public.reports (reporter_id, message_id, listing_id, reported_user_id)
  nulls not distinct where status = 'open' and source = 'member';

-- Admins are marked here by SQL only. The private schema is not exposed through the Data API.
create table private.admins (
  user_id uuid primary key references auth.users on delete cascade,
  added_at timestamptz not null default now()
);

create policy "parties see their threads" on public.threads for select to authenticated
  using ((select auth.uid()) in (buyer_id, seller_id));
create policy "parties see messages, held ones only their own" on public.messages for select to authenticated
  using (
    exists (select 1 from public.threads t where t.id = thread_id and (select auth.uid()) in (t.buyer_id, t.seller_id))
    and (not held or sender_id = (select auth.uid()))
  );
-- Both sides see a block, so listings can hide both ways and the blocked side knows the thread ended.
create policy "users see blocks they are part of" on public.blocks for select to authenticated
  using ((select auth.uid()) in (blocker_id, blocked_id));
create policy "reporters see their own reports" on public.reports for select to authenticated
  using (reporter_id = (select auth.uid()));

revoke all on public.threads, public.messages, public.blocks, public.reports from anon, authenticated;
grant select on public.threads, public.messages, public.blocks to authenticated;
grant select (id, message_id, listing_id, reported_user_id, reason, note, status, created_at) on public.reports to authenticated;

-- Listings hide both ways once either side blocks the other.
drop policy "members see active listings and their own" on public.listings;
create policy "members see active listings and their own" on public.listings for select to authenticated
  using (
    seller_id = (select auth.uid())
    or (status = 'active'
        and exists (select 1 from public.memberships m where m.user_id = (select auth.uid()))
        and not exists (select 1 from public.blocks b
                        where (b.blocker_id = (select auth.uid()) and b.blocked_id = seller_id)
                           or (b.blocked_id = (select auth.uid()) and b.blocker_id = seller_id)))
  );

-- Realtime postgres_changes checks the subscriber's SELECT policy on every row, so the policy
-- above is the channel's access control: a third member or anon receives nothing.
alter publication supabase_realtime add table public.messages;

create or replace function private.is_suspended(p_uid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from auth.users u where u.id = p_uid and u.banned_until > now());
$$;

-- A suspended user's JWT stays valid until it expires; refuse new listings from them on every path.
create or replace function private.refuse_suspended_seller()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if private.is_suspended(new.seller_id) then
    raise exception 'Your account is suspended.' using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger listings_refuse_suspended before insert on public.listings
  for each row execute function private.refuse_suspended_seller();

create or replace function private.blocked_between(p_a uuid, p_b uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (select 1 from public.blocks b
                 where (b.blocker_id = p_a and b.blocked_id = p_b) or (b.blocker_id = p_b and b.blocked_id = p_a));
$$;

-- Every check a send must pass, cheap ones first. Raises; returns the thread.
create or replace function private.chat_guard(p_uid uuid, p_thread uuid)
returns public.threads
language plpgsql
set search_path = ''
as $$
declare
  v_thread public.threads;
  v_cfg public.config;
begin
  if p_uid is null or not exists (select 1 from public.memberships m where m.user_id = p_uid) then
    raise exception 'Finish sign-up first' using errcode = '42501';
  end if;
  if private.is_suspended(p_uid) then
    raise exception 'Your account is suspended.' using errcode = '42501';
  end if;
  select * into v_thread from public.threads t where t.id = p_thread and p_uid in (t.buyer_id, t.seller_id);
  if not found then
    raise exception 'Conversation not found' using errcode = '42501';
  end if;
  if v_thread.closed_at is not null or private.blocked_between(v_thread.buyer_id, v_thread.seller_id) then
    raise exception 'This conversation has ended.' using errcode = '42501';
  end if;

  v_cfg := private.config_for((select m.school_id from public.memberships m where m.user_id = p_uid));
  -- Serialize per user so parallel sends can't all pass the counts below.
  perform pg_advisory_xact_lock(hashtextextended('messages:' || p_uid::text, 0));
  if (select count(*) from public.messages msg
      where msg.sender_id = p_uid and msg.created_at > now() - interval '1 hour') >= v_cfg.msg_user_per_hour then
    raise exception 'You''re sending messages too fast. Try again later.' using errcode = '54000';
  end if;
  if (select count(*) from public.messages msg
      where msg.thread_id = p_thread and msg.sender_id = p_uid
        and msg.created_at > now() - interval '1 minute') >= v_cfg.msg_thread_per_minute then
    raise exception 'Slow down a little. Try again in a minute.' using errcode = '54000';
  end if;
  return v_thread;
end;
$$;

-- Cheap pre-check the server action runs before calling moderation.
create or replace function public.can_send_message(p_thread uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.chat_guard((select auth.uid()), p_thread);
end;
$$;

-- Server only (secret key): the server action passes the signed-in sender after moderation.
-- Re-runs every guard under the lock, so the pre-check can't be raced.
create or replace function public.send_message(p_sender uuid, p_thread uuid, p_body text, p_flags text[], p_nudge boolean)
returns public.messages
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_thread public.threads;
  v_msg public.messages;
  v_body text := trim(coalesce(p_body, ''));
  v_held boolean := coalesce(cardinality(p_flags), 0) > 0;
begin
  if char_length(v_body) not between 1 and 2000 then
    raise exception 'Messages are 1 to 2000 characters.' using errcode = '22023';
  end if;
  v_thread := private.chat_guard(p_sender, p_thread);

  insert into public.messages (thread_id, sender_id, body, held, nudge)
  values (p_thread, p_sender, v_body, v_held, coalesce(p_nudge, false))
  returning * into v_msg;
  if v_held then
    insert into public.reports (source, message_id, listing_id, reported_user_id, reason, quoted, flags)
    values ('moderation', v_msg.id, v_thread.listing_id, p_sender, 'moderation', v_body, p_flags);
  else
    update public.threads set last_message_at = v_msg.created_at where id = p_thread;
  end if;
  return v_msg;
end;
$$;

-- Opens (or returns) the caller's thread on a listing.
create or replace function public.open_thread(p_listing uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_listing public.listings;
  v_id uuid;
begin
  if v_uid is null or not exists (select 1 from public.memberships m where m.user_id = v_uid) then
    raise exception 'Finish sign-up first' using errcode = '42501';
  end if;
  if private.is_suspended(v_uid) then
    raise exception 'Your account is suspended.' using errcode = '42501';
  end if;
  select * into v_listing from public.listings l where l.id = p_listing;
  if found and v_listing.seller_id = v_uid then
    raise exception 'This is your own listing.' using errcode = '22023';
  end if;
  -- An existing thread survives the listing going pending or sold (M3 offers live in it).
  select t.id into v_id from public.threads t where t.listing_id = p_listing and t.buyer_id = v_uid;
  if v_id is not null and v_listing.status <> 'removed' and not private.blocked_between(v_uid, v_listing.seller_id) then
    return v_id;
  end if;
  -- New threads only on listings the caller can see: active, and no block either way.
  if v_listing.id is null or v_listing.status <> 'active' or private.blocked_between(v_uid, v_listing.seller_id) then
    raise exception 'Listing not found' using errcode = 'P0002';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('threads:' || v_uid::text, 0));
  if (select count(*) from public.threads t where t.buyer_id = v_uid and t.created_at > now() - interval '1 hour')
     >= (private.config_for((select m.school_id from public.memberships m where m.user_id = v_uid))).threads_per_hour then
    raise exception 'You''ve started a lot of conversations. Try again in an hour.' using errcode = '54000';
  end if;

  insert into public.threads (listing_id, buyer_id, seller_id)
  values (p_listing, v_uid, v_listing.seller_id)
  on conflict (listing_id, buyer_id) do nothing
  returning id into v_id;
  if v_id is null then
    select t.id into v_id from public.threads t where t.listing_id = p_listing and t.buyer_id = v_uid;
  end if;
  return v_id;
end;
$$;

-- Blocking ends every thread between the two users, both ways.
create or replace function public.block_user(p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null or not exists (select 1 from public.memberships m where m.user_id = v_uid) then
    raise exception 'Finish sign-up first' using errcode = '42501';
  end if;
  if p_user is null or p_user = v_uid then
    raise exception 'You can''t block yourself.' using errcode = '22023';
  end if;
  -- Only people you've talked to can be blocked, so the function can't probe for user ids.
  if not exists (select 1 from public.threads t
                 where (t.buyer_id = v_uid and t.seller_id = p_user) or (t.seller_id = v_uid and t.buyer_id = p_user)) then
    raise exception 'User not found' using errcode = 'P0002';
  end if;
  insert into public.blocks (blocker_id, blocked_id) values (v_uid, p_user) on conflict do nothing;
  update public.threads t set closed_at = now()
  where t.closed_at is null
    and ((t.buyer_id = v_uid and t.seller_id = p_user) or (t.seller_id = v_uid and t.buyer_id = p_user));
end;
$$;

-- Report exactly one of: a message in your thread, a listing you can see, or someone you've talked to.
-- The reporter is always the caller.
create or replace function public.report(
  p_reason text, p_note text default null,
  p_message_id bigint default null, p_listing_id uuid default null, p_user_id uuid default null)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_cfg public.config;
  v_listing uuid := p_listing_id;
  v_user uuid := p_user_id;
  v_quoted text;
  v_id bigint;
begin
  if v_uid is null or not exists (select 1 from public.memberships m where m.user_id = v_uid) then
    raise exception 'Finish sign-up first' using errcode = '42501';
  end if;
  if num_nonnulls(p_message_id, p_listing_id, p_user_id) <> 1 then
    raise exception 'Report one message, listing or user.' using errcode = '22023';
  end if;
  if p_reason is null or p_reason = 'moderation' then
    raise exception 'Pick a reason.' using errcode = '22023';
  end if;

  if p_message_id is not null then
    -- Must be a message the caller can see in their own thread, sent by the other person.
    select msg.body, t.listing_id, msg.sender_id into v_quoted, v_listing, v_user
    from public.messages msg join public.threads t on t.id = msg.thread_id
    where msg.id = p_message_id and v_uid in (t.buyer_id, t.seller_id)
      and msg.sender_id <> v_uid and not msg.held;
    if not found then
      raise exception 'Message not found' using errcode = 'P0002';
    end if;
  elsif p_listing_id is not null then
    select l.seller_id into v_user from public.listings l
    where l.id = p_listing_id and l.status = 'active' and l.seller_id <> v_uid
      and not private.blocked_between(v_uid, l.seller_id);
    if not found then
      raise exception 'Listing not found' using errcode = 'P0002';
    end if;
  elsif not exists (select 1 from public.threads t
                    where (t.buyer_id = v_uid and t.seller_id = p_user_id) or (t.seller_id = v_uid and t.buyer_id = p_user_id)) then
    raise exception 'User not found' using errcode = 'P0002';
  end if;

  v_cfg := private.config_for((select m.school_id from public.memberships m where m.user_id = v_uid));
  perform pg_advisory_xact_lock(hashtextextended('reports:' || v_uid::text, 0));
  if (select count(*) from public.reports r
      where r.reporter_id = v_uid and r.created_at > now() - interval '1 day') >= v_cfg.reports_per_day then
    raise exception 'You''ve sent a lot of reports today. We''re on it.' using errcode = '54000';
  end if;

  insert into public.reports (reporter_id, message_id, listing_id, reported_user_id, reason, note, quoted)
  values (v_uid, p_message_id, v_listing, v_user, p_reason, nullif(trim(p_note), ''), v_quoted)
  on conflict (reporter_id, message_id, listing_id, reported_user_id) where status = 'open' and source = 'member'
  do nothing
  returning id into v_id;
  -- Already reported and still open: return that report instead of a duplicate.
  if v_id is null then
    select r.id into v_id from public.reports r
    where r.reporter_id = v_uid and r.status = 'open' and r.source = 'member'
      and r.message_id is not distinct from p_message_id and r.listing_id is not distinct from v_listing
      and r.reported_user_id is not distinct from v_user;
  end if;
  return v_id;
end;
$$;

-- Admin functions. Each refuses anyone not in private.admins.
create or replace function private.require_admin()
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null or not exists (select 1 from private.admins a where a.user_id = v_uid) then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
  return v_uid;
end;
$$;

create or replace function public.admin_reports()
returns table (id bigint, source text, reason text, note text, quoted text, flags text[], status text, created_at timestamptz,
               message_id bigint, listing_id uuid, listing_title text, listing_status text,
               reported_user_id uuid, reported_email text, reported_suspended boolean, reporter_email text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  return query
    select r.id, r.source, r.reason, r.note, r.quoted, r.flags, r.status, r.created_at,
           r.message_id, r.listing_id, l.title, l.status,
           r.reported_user_id, rm.email, private.is_suspended(r.reported_user_id), pm.email
    from public.reports r
    left join public.listings l on l.id = r.listing_id
    left join public.memberships rm on rm.user_id = r.reported_user_id
    left join public.memberships pm on pm.user_id = r.reporter_id
    order by r.status = 'open' desc, r.created_at desc
    limit 200;
end;
$$;

create or replace function public.admin_stats()
returns table (open_reports bigint, nudged_messages_7d bigint, held_messages_7d bigint)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_admin();
  return query select
    (select count(*) from public.reports r where r.status = 'open'),
    (select count(*) from public.messages m where m.nudge and m.created_at > now() - interval '7 days'),
    (select count(*) from public.messages m where m.held and m.created_at > now() - interval '7 days');
end;
$$;

-- p_action: 'dismiss', 'hide_listing' (status -> removed) or 'suspend_user' (Auth ban + listings removed).
create or replace function public.admin_resolve_report(p_report bigint, p_action text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_report public.reports;
begin
  select * into v_report from public.reports r where r.id = p_report for update;
  if not found then
    raise exception 'Report not found' using errcode = 'P0002';
  end if;
  if v_report.status <> 'open' then
    raise exception 'This report is already resolved.' using errcode = '22023';
  end if;
  if p_action = 'hide_listing' then
    if v_report.listing_id is null then
      raise exception 'This report has no listing.' using errcode = '22023';
    end if;
    update public.listings set status = 'removed' where id = v_report.listing_id;
  elsif p_action = 'suspend_user' then
    if v_report.reported_user_id is null then
      raise exception 'This report has no user.' using errcode = '22023';
    end if;
    -- Supabase Auth refuses sign-in and token refresh for a banned user; existing tokens run out within the JWT expiry.
    update auth.users set banned_until = 'infinity' where id = v_report.reported_user_id;
    update public.listings set status = 'removed' where seller_id = v_report.reported_user_id and status <> 'sold';
  elsif p_action is distinct from 'dismiss' then
    raise exception 'Unknown action' using errcode = '22023';
  end if;
  update public.reports
  set status = case when p_action = 'dismiss' then 'dismissed' else 'actioned' end,
      resolved_by = v_admin, resolved_at = now()
  where id = p_report;
end;
$$;

revoke execute on function public.can_send_message(uuid), public.send_message(uuid, uuid, text, text[], boolean),
  public.open_thread(uuid), public.block_user(uuid), public.report(text, text, bigint, uuid, uuid),
  public.admin_reports(), public.admin_stats(), public.admin_resolve_report(bigint, text)
  from public, anon, authenticated;
grant execute on function public.can_send_message(uuid), public.open_thread(uuid), public.block_user(uuid),
  public.report(text, text, bigint, uuid, uuid),
  public.admin_reports(), public.admin_stats(), public.admin_resolve_report(bigint, text) to authenticated;
grant execute on function public.send_message(uuid, uuid, text, text[], boolean) to service_role;
