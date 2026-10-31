-- Later ideas from M1/M2: edit/remove a listing, unblock, a realtime "thread ended" event, admin queue paging and
-- filters, read receipts. Same rules as before: clients only SELECT; writes go through functions.

-- ===== Edit and remove a listing =====
-- Server only (secret key), like send_message: the server action moderates the new text first, so the edit
-- can't skip moderation by calling the database directly.
create or replace function public.update_listing(
  p_seller uuid, p_listing uuid, p_title text, p_description text, p_price_cents int, p_category text)
returns public.listings
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_listing public.listings;
  v_cfg public.config;
  v_reason text;
begin
  if p_seller is null or not exists (select 1 from public.memberships m where m.user_id = p_seller) then
    raise exception 'Finish sign-up first' using errcode = '42501';
  end if;
  if private.is_suspended(p_seller) then
    raise exception 'Your account is suspended.' using errcode = '42501';
  end if;
  select * into v_listing from public.listings l where l.id = p_listing and l.seller_id = p_seller for update;
  if not found then
    raise exception 'Listing not found' using errcode = 'P0002';
  end if;
  if v_listing.status in ('sold', 'removed') then
    raise exception 'Sold or removed listings can''t be edited.' using errcode = '22023';
  end if;
  if v_listing.status = 'pending' and p_price_cents is distinct from v_listing.price_cents then
    raise exception 'An offer is accepted, so the price is locked until the trade completes or is cancelled.' using errcode = '22023';
  end if;
  v_cfg := private.config_for(v_listing.school_id);
  if p_price_cents is null or p_price_cents < v_cfg.min_price_cents then
    raise exception 'The minimum price is %.', private.money(v_cfg.min_price_cents) using errcode = '22023';
  end if;
  if char_length(trim(coalesce(p_title, ''))) not between 3 and 80 then
    raise exception 'Give it a title between 3 and 80 characters.' using errcode = '22023';
  end if;
  v_reason := private.prohibited_reason(coalesce(p_title, '') || ' ' || coalesce(p_description, ''));
  if v_reason is not null then
    raise exception '%', v_reason using errcode = '22023';
  end if;

  update public.listings
  set title = trim(p_title), description = trim(coalesce(p_description, '')), price_cents = p_price_cents, category = p_category
  where id = p_listing
  returning * into v_listing;
  return v_listing;
end;
$$;

-- The seller takes a listing down. Not while an offer is accepted (cancel the trade first); pending offers are declined.
create or replace function public.remove_listing(p_listing uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_listing public.listings;
  v_offer public.offers;
begin
  if v_uid is null or not exists (select 1 from public.memberships m where m.user_id = v_uid) then
    raise exception 'Finish sign-up first' using errcode = '42501';
  end if;
  select * into v_listing from public.listings l where l.id = p_listing and l.seller_id = v_uid for update;
  if not found then
    raise exception 'Listing not found' using errcode = 'P0002';
  end if;
  if v_listing.status = 'removed' then
    return;
  end if;
  if v_listing.status = 'pending' then
    raise exception 'An offer is accepted. Cancel the trade in the chat first.' using errcode = '22023';
  end if;
  if v_listing.status = 'sold' then
    raise exception 'Sold listings stay up as a record.' using errcode = '22023';
  end if;
  for v_offer in select * from public.offers o where o.listing_id = p_listing and o.state = 'pending' order by o.id for update loop
    update public.offers set state = 'declined', ended_at = now() where id = v_offer.id;
    perform private.post_event(v_offer, v_uid, 'declined', 'Declined: the seller took this listing down');
  end loop;
  update public.listings set status = 'removed' where id = p_listing;
end;
$$;

-- ===== Thread ended: a system event the other side receives live =====
alter table public.messages drop constraint messages_event_has_offer;
alter table public.messages drop constraint messages_event_check;
alter table public.messages
  add constraint messages_event_check
    check (event in ('offer', 'accepted', 'declined', 'withdrawn', 'expired', 'cancelled', 'completed', 'ended')),
  -- Offer events carry their offer; 'ended' is about the thread; plain messages carry neither.
  add constraint messages_event_has_offer
    check ((event is null and offer_id is null) or (event = 'ended' and offer_id is null) or (event <> 'ended' and offer_id is not null));

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
  if not exists (select 1 from public.threads t
                 where (t.buyer_id = v_uid and t.seller_id = p_user) or (t.seller_id = v_uid and t.buyer_id = p_user)) then
    raise exception 'User not found' using errcode = 'P0002';
  end if;
  insert into public.blocks (blocker_id, blocked_id) values (v_uid, p_user) on conflict do nothing;
  -- Close the threads first (make_offer locks the thread row), then tell both sides live. The event doesn't say who blocked.
  with closed as (
    update public.threads t set closed_at = now()
    where t.closed_at is null
      and ((t.buyer_id = v_uid and t.seller_id = p_user) or (t.seller_id = v_uid and t.buyer_id = p_user))
    returning t.id
  )
  insert into public.messages (thread_id, sender_id, body, event)
  select id, null, 'This conversation has ended.', 'ended' from closed;
  perform private.end_live_offers(v_uid, p_user);
end;
$$;

-- ===== Unblock: the blocker only. Reopens nothing by itself =====
-- Listings show again both ways; the closed thread stays closed until the buyer messages from the listing again.
create or replace function public.unblock_user(p_user uuid)
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
  delete from public.blocks b where b.blocker_id = v_uid and b.blocked_id = p_user;
  if not found then
    raise exception 'You haven''t blocked this person.' using errcode = 'P0002';
  end if;
end;
$$;

-- open_thread: messaging from the listing again reopens the buyer's closed thread, once no block stands either way.
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
    update public.threads set closed_at = null where id = v_id and closed_at is not null;
    return v_id;
  end if;
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

-- ===== Read receipts: one timestamp per party, visible only to the two of them (threads RLS) =====
alter table public.threads
  add column buyer_read_at timestamptz,
  add column seller_read_at timestamptz;

create or replace function public.mark_thread_read(p_thread uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  update public.threads t
  set buyer_read_at = case when t.buyer_id = v_uid then now() else t.buyer_read_at end,
      seller_read_at = case when t.seller_id = v_uid then now() else t.seller_read_at end
  where t.id = p_thread and v_uid in (t.buyer_id, t.seller_id);
end;
$$;

-- The other side sees "Seen" live. Realtime checks the threads SELECT policy per row: parties only.
alter publication supabase_realtime add table public.threads;

-- ===== Admin queue: filters and paging past 200 =====
drop function public.admin_reports();
create or replace function public.admin_reports(
  p_status text default null, p_source text default null, p_reason text default null,
  p_before bigint default null, p_limit int default 50)
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
  -- Newest first by id, so "older" is a stable cursor (p_before = the last id on the page).
  return query
    select r.id, r.source, r.reason, r.note, r.quoted, r.flags, r.status, r.created_at,
           r.message_id, r.listing_id, l.title, l.status,
           r.reported_user_id, rm.email, private.is_suspended(r.reported_user_id), pm.email
    from public.reports r
    left join public.listings l on l.id = r.listing_id
    left join public.memberships rm on rm.user_id = r.reported_user_id
    left join public.memberships pm on pm.user_id = r.reporter_id
    where (p_status is null or r.status = p_status)
      and (p_source is null or r.source = p_source)
      and (p_reason is null or r.reason = p_reason)
      and (p_before is null or r.id < p_before)
    order by r.id desc
    limit least(greatest(coalesce(p_limit, 50), 1), 200);
end;
$$;
create index reports_id_status_idx on public.reports (status, id desc);

revoke execute on function public.update_listing(uuid, uuid, text, text, int, text), public.remove_listing(uuid),
  public.unblock_user(uuid), public.mark_thread_read(uuid), public.admin_reports(text, text, text, bigint, int)
  from public, anon, authenticated;
grant execute on function public.remove_listing(uuid), public.unblock_user(uuid), public.mark_thread_read(uuid),
  public.admin_reports(text, text, text, bigint, int) to authenticated;
grant execute on function public.update_listing(uuid, uuid, text, text, int, text) to service_role;
