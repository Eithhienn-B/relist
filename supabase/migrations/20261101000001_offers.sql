-- M3: offers, handoff codes, trades, payment events, 4-day expiry.
-- Clients only SELECT (offers, trades, payment events: parties only). Every transition is a security definer
-- function that takes the actor from auth.uid(); a trigger on offers refuses any state jump the machine doesn't allow,
-- and a second refuses offers that aren't born pending, so even a buggy function or the secret key can't skip a step.

create extension if not exists pg_cron;

alter table public.config
  add column offers_per_hour int not null default 10 check (offers_per_hour > 0),
  add column handoff_max_wrong int not null default 5 check (handoff_max_wrong > 0); -- wrong codes per offer per 10 min

-- A thread's buyer keeps reading its listing while it's pending or sold, so history stays whole. Removed or blocked still hides it.
drop policy "members see active listings and their own" on public.listings;
create policy "members see active listings and their own" on public.listings for select to authenticated
  using (
    seller_id = (select auth.uid())
    or (((status = 'active' and exists (select 1 from public.memberships m where m.user_id = (select auth.uid())))
         or (status <> 'removed' and exists (select 1 from public.threads t
                                             where t.listing_id = listings.id and t.buyer_id = (select auth.uid()))))
        and not exists (select 1 from public.blocks b
                        where (b.blocker_id = (select auth.uid()) and b.blocked_id = seller_id)
                           or (b.blocked_id = (select auth.uid()) and b.blocker_id = seller_id)))
  );

create table public.offers (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.threads on delete cascade,
  listing_id uuid not null references public.listings on delete cascade,
  buyer_id uuid not null references auth.users on delete cascade,
  seller_id uuid not null references auth.users on delete cascade,
  amount_cents int not null check (amount_cents between 1 and 1000000),
  state text not null default 'pending'
    check (state in ('pending', 'accepted', 'declined', 'withdrawn', 'expired', 'cancelled', 'completed')),
  payment_ref text, -- PaymentIntent id in M4; the stub writes pi_stub_<offer>
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  expires_at timestamptz, -- accept + config.offer_window
  ended_at timestamptz,
  check (buyer_id <> seller_id),
  check (state not in ('accepted', 'expired', 'completed') or (accepted_at is not null and expires_at is not null))
);
-- One live offer per buyer per listing; one accepted offer per listing (the backstop behind the listing row lock).
create unique index offers_one_live_per_buyer on public.offers (listing_id, buyer_id) where state in ('pending', 'accepted');
create unique index offers_one_accepted_per_listing on public.offers (listing_id) where state = 'accepted';
create index offers_thread_idx on public.offers (thread_id, created_at);
create index offers_listing_idx on public.offers (listing_id);
create index offers_buyer_idx on public.offers (buyer_id, created_at desc);
create index offers_seller_idx on public.offers (seller_id);
create index offers_expiry_idx on public.offers (expires_at) where state = 'accepted';

create or replace function private.offer_transition_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (new.thread_id, new.listing_id, new.buyer_id, new.seller_id, new.amount_cents, new.created_at)
     is distinct from (old.thread_id, old.listing_id, old.buyer_id, old.seller_id, old.amount_cents, old.created_at) then
    raise exception 'Offers can''t be edited.' using errcode = '22023';
  end if;
  if new.state is distinct from old.state and (old.state, new.state) not in (
      ('pending', 'accepted'), ('pending', 'declined'), ('pending', 'withdrawn'), ('pending', 'cancelled'),
      ('accepted', 'cancelled'), ('accepted', 'expired'), ('accepted', 'completed')) then
    raise exception 'An offer can''t go from % to %.', old.state, new.state using errcode = '22023';
  end if;
  -- The 4-day window is fixed at accept. (Tests fake time with session_replication_role = replica.)
  if old.accepted_at is not null and (new.accepted_at, new.expires_at) is distinct from (old.accepted_at, old.expires_at) then
    raise exception 'The meetup window can''t be changed.' using errcode = '22023';
  end if;
  if new.state = 'completed' and old.state <> 'completed'
     and not exists (select 1 from public.trades t where t.offer_id = new.id) then
    raise exception 'An offer completes only with its trade.' using errcode = '22023';
  end if;
  return new;
end;
$$;
create trigger offers_transition_guard before update on public.offers
  for each row execute function private.offer_transition_guard();

-- Every offer is born pending, with no accept or expiry stamped on it.
create or replace function private.offer_insert_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.state <> 'pending' or new.accepted_at is not null or new.expires_at is not null or new.ended_at is not null then
    raise exception 'Offers start pending.' using errcode = '22023';
  end if;
  return new;
end;
$$;
create trigger offers_insert_guard before insert on public.offers
  for each row execute function private.offer_insert_guard();

-- Written once, on a successful handoff scan.
create table public.trades (
  id bigint generated always as identity primary key,
  -- restrict, not cascade: deleting a user or listing must not erase the money trail.
  offer_id uuid not null unique references public.offers on delete restrict,
  listing_id uuid not null references public.listings on delete restrict,
  buyer_id uuid not null references auth.users on delete restrict,
  seller_id uuid not null references auth.users on delete restrict,
  amount_cents int not null,
  fee_cents int not null check (fee_cents >= 0 and fee_cents <= amount_cents),
  created_at timestamptz not null default now(),
  captured_at timestamptz -- set when the payment provider confirms the capture
);
create index trades_listing_idx on public.trades (listing_id);
create index trades_buyer_idx on public.trades (buyer_id);
create index trades_seller_idx on public.trades (seller_id);

-- What the payment provider is asked to do, written in the same transaction as the transition (an outbox).
-- (offer_id, kind) is unique, so each ask happens once; it becomes the Stripe idempotency key in M4.
create table public.payment_events (
  id bigint generated always as identity primary key,
  offer_id uuid not null references public.offers on delete restrict,
  kind text not null check (kind in ('authorize', 'capture', 'cancel', 'refund')),
  amount_cents int not null,
  fee_cents int not null default 0,
  status text not null default 'requested' check (status in ('requested', 'succeeded', 'failed')),
  provider_ref text,
  error text,
  created_at timestamptz not null default now(),
  processed_at timestamptz,
  unique (offer_id, kind)
);
create index payment_events_requested_idx on public.payment_events (created_at) where status = 'requested';

-- Server-side only: lives outside the Data API, no client role has any privilege on it.
create table private.handoff_codes (
  offer_id uuid primary key references public.offers on delete cascade,
  secret bytea not null default extensions.gen_random_bytes(20),
  failed_count int not null default 0,
  failed_since timestamptz,
  total_failed int not null default 0 -- lifetime: 20 wrong codes locks the offer for good
);
revoke all on private.handoff_codes from public, anon, authenticated, service_role;

-- Offer events are chat rows, so they reach the thread through the same RLS and realtime path as messages.
alter table public.messages
  alter column sender_id drop not null, -- null only for system events (expiry)
  add column event text check (event in ('offer', 'accepted', 'declined', 'withdrawn', 'expired', 'cancelled', 'completed')),
  add column offer_id uuid references public.offers on delete cascade,
  add constraint messages_sender_or_event check (sender_id is not null or event is not null),
  add constraint messages_event_has_offer check ((event is null) = (offer_id is null));
create index messages_offer_idx on public.messages (offer_id) where offer_id is not null;

create policy "parties see their offers" on public.offers for select to authenticated
  using ((select auth.uid()) in (buyer_id, seller_id));
create policy "parties see their trades" on public.trades for select to authenticated
  using ((select auth.uid()) in (buyer_id, seller_id));
create policy "parties see their payment events" on public.payment_events for select to authenticated
  using (exists (select 1 from public.offers o where o.id = offer_id and (select auth.uid()) in (o.buyer_id, o.seller_id)));

revoke all on public.offers, public.trades, public.payment_events from anon, authenticated;
-- The secret key reads these and reports results through payment_result(); it never writes them directly.
revoke insert, update, delete, truncate on public.offers, public.trades, public.payment_events from service_role;
grant select on public.offers, public.trades to authenticated;
grant select (id, offer_id, kind, amount_cents, fee_cents, status, created_at, processed_at) on public.payment_events to authenticated;

-- Fee in integer cents, round half up: $10.00 -> 0, $10.01 at 5% -> 50.
create or replace function private.fee_cents(p_amount int, p_fee_bps int, p_threshold int)
returns int
language sql
immutable
set search_path = ''
as $$
  select case when p_amount > p_threshold then ((p_amount::bigint * p_fee_bps + 5000) / 10000)::int else 0 end;
$$;

create or replace function private.money(p_cents int)
returns text
language sql
immutable
set search_path = ''
as $$
  select '$' || to_char(p_cents / 100.0, 'FM999990.00');
$$;

-- TOTP-style: 6 digits from HMAC-SHA256(secret, 30-second window number).
create or replace function private.handoff_window(p_at timestamptz)
returns bigint
language sql
immutable
set search_path = ''
as $$
  select floor(extract(epoch from p_at) / 30)::bigint;
$$;

create or replace function private.handoff_code_at(p_secret bytea, p_window bigint)
returns text
language sql
immutable
set search_path = ''
as $$
  select lpad(((('x' || encode(substring(extensions.hmac(convert_to(p_window::text, 'UTF8'), p_secret, 'sha256') from 1 for 4), 'hex'))::bit(32)::bigint
               & 2147483647) % 1000000)::text, 6, '0');
$$;

-- Digits only, after folding fullwidth (NFKC) and Arabic-Indic digits to ASCII, so "12 34 56" and "１２３４５６" count.
create or replace function private.digits(p_body text)
returns text
language sql
immutable
set search_path = ''
as $$
  select regexp_replace(translate(normalize(p_body, NFKC), '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹', '01234567890123456789'), '[^0-9]', '', 'g');
$$;

-- If the text holds the current or previous code of a live offer in the thread, that code is burned:
-- the secret rotates (the leaked code is dead at once) and the offer takes a strike toward the redeem lockout.
-- Returns true when it caught one. Rotating on every hit is what keeps this from being an oracle: a probe that
-- finds the code destroys it, and a probe that misses is a real, rate-limited message the buyer can read.
create or replace function private.catch_handoff_code(p_thread uuid, p_body text)
returns boolean
language plpgsql
set search_path = ''
as $$
declare
  v_digits text := private.digits(p_body);
  v_window bigint := private.handoff_window(now());
  v_hits int;
begin
  if char_length(v_digits) < 6 then
    return false;
  end if;
  update private.handoff_codes h
  set secret = extensions.gen_random_bytes(20),
      failed_count = case when h.failed_since > now() - interval '10 minutes' then h.failed_count + 1 else 1 end,
      failed_since = case when h.failed_since > now() - interval '10 minutes' then h.failed_since else now() end
  from public.offers o
  where o.id = h.offer_id and o.thread_id = p_thread and o.state = 'accepted'
    and (strpos(v_digits, private.handoff_code_at(h.secret, v_window)) > 0
         or strpos(v_digits, private.handoff_code_at(h.secret, v_window - 1)) > 0);
  get diagnostics v_hits = row_count;
  return v_hits > 0;
end;
$$;

create or replace function private.post_event(p_offer public.offers, p_sender uuid, p_event text, p_body text)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_at timestamptz;
begin
  insert into public.messages (thread_id, sender_id, body, event, offer_id)
  values (p_offer.thread_id, p_sender, p_body, p_event, p_offer.id)
  returning created_at into v_at;
  update public.threads set last_message_at = v_at where id = p_offer.thread_id;
end;
$$;

-- The checks every offer action shares. Returns the offer, locked, if the caller is a party.
create or replace function private.offer_for(p_uid uuid, p_offer uuid)
returns public.offers
language plpgsql
set search_path = ''
as $$
declare
  v_offer public.offers;
begin
  if p_uid is null or not exists (select 1 from public.memberships m where m.user_id = p_uid) then
    raise exception 'Finish sign-up first' using errcode = '42501';
  end if;
  if private.is_suspended(p_uid) then
    raise exception 'Your account is suspended.' using errcode = '42501';
  end if;
  select * into v_offer from public.offers o where o.id = p_offer and p_uid in (o.buyer_id, o.seller_id) for update;
  if not found then
    raise exception 'Offer not found' using errcode = 'P0002';
  end if;
  return v_offer;
end;
$$;

-- An accepted offer ends without a trade: cancel the authorization, free the listing, drop the code.
create or replace function private.release_offer(p_offer public.offers, p_state text, p_actor uuid, p_body text)
returns void
language plpgsql
set search_path = ''
as $$
begin
  update public.offers set state = p_state, ended_at = now() where id = p_offer.id;
  if p_offer.state = 'accepted' then
    update public.listings set status = 'active' where id = p_offer.listing_id and status = 'pending';
    delete from private.handoff_codes where offer_id = p_offer.id;
    insert into public.payment_events (offer_id, kind, amount_cents) values (p_offer.id, 'cancel', p_offer.amount_cents)
    on conflict (offer_id, kind) do nothing;
  end if;
  perform private.post_event(p_offer, p_actor, p_state, p_body);
end;
$$;

create or replace function public.make_offer(p_thread uuid, p_amount_cents int)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_thread public.threads;
  v_listing public.listings;
  v_cfg public.config;
  v_offer public.offers;
begin
  if v_uid is null or not exists (select 1 from public.memberships m where m.user_id = v_uid) then
    raise exception 'Finish sign-up first' using errcode = '42501';
  end if;
  if private.is_suspended(v_uid) then
    raise exception 'Your account is suspended.' using errcode = '42501';
  end if;
  -- Thread row lock: a block (which closes the thread first) can't slip in between this check and the insert.
  select * into v_thread from public.threads t where t.id = p_thread and v_uid in (t.buyer_id, t.seller_id) for update;
  if not found then
    raise exception 'Conversation not found' using errcode = '42501';
  end if;
  if v_thread.seller_id = v_uid then
    raise exception 'You can''t make an offer on your own listing.' using errcode = '22023';
  end if;
  if v_thread.closed_at is not null or private.blocked_between(v_thread.buyer_id, v_thread.seller_id) then
    raise exception 'This conversation has ended.' using errcode = '42501';
  end if;
  select * into v_listing from public.listings l where l.id = v_thread.listing_id for update;
  if v_listing.status <> 'active' then
    raise exception 'This listing isn''t taking offers.' using errcode = '22023';
  end if;
  v_cfg := private.config_for(v_listing.school_id);
  if p_amount_cents is null or p_amount_cents < v_cfg.min_price_cents or p_amount_cents > 1000000 then
    raise exception 'Offers are % to $10000.', private.money(v_cfg.min_price_cents) using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('offers:' || v_uid::text, 0));
  if exists (select 1 from public.offers o
             where o.listing_id = v_listing.id and o.buyer_id = v_uid and o.state in ('pending', 'accepted')) then
    raise exception 'You already have an offer on this. Withdraw it first.' using errcode = '22023';
  end if;
  if (select count(*) from public.offers o where o.buyer_id = v_uid and o.created_at > now() - interval '1 hour')
     >= v_cfg.offers_per_hour then
    raise exception 'You''ve made a lot of offers. Try again in an hour.' using errcode = '54000';
  end if;

  insert into public.offers (thread_id, listing_id, buyer_id, seller_id, amount_cents)
  values (v_thread.id, v_listing.id, v_uid, v_listing.seller_id, p_amount_cents)
  returning * into v_offer;
  perform private.post_event(v_offer, v_uid, 'offer', 'Offered ' || private.money(p_amount_cents));
  return v_offer.id;
end;
$$;

create or replace function public.accept_offer(p_offer uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_offer public.offers;
  v_listing public.listings;
  v_other public.offers;
begin
  -- Lock order: listing, then offers. Locking the offer first deadlocked two parallel accepts
  -- (each held its own offer and waited for the listing the other held; scripts/parallel-accept.sh).
  -- The listing row lock serializes parallel accepts; offers_one_accepted_per_listing backs it up.
  select * into v_listing from public.listings l
  where l.id = (select o.listing_id from public.offers o where o.id = p_offer and v_uid in (o.buyer_id, o.seller_id))
  for update;
  v_offer := private.offer_for(v_uid, p_offer);
  if v_offer.seller_id <> v_uid then
    raise exception 'Only the seller can accept an offer.' using errcode = '42501';
  end if;
  if v_offer.state <> 'pending' then
    raise exception 'This offer is already %.', v_offer.state using errcode = '22023';
  end if;
  if private.blocked_between(v_offer.buyer_id, v_offer.seller_id) then
    raise exception 'This conversation has ended.' using errcode = '42501';
  end if;
  if private.is_suspended(v_offer.buyer_id) then
    raise exception 'This buyer can''t trade right now.' using errcode = '42501';
  end if;
  if v_listing.status <> 'active' then
    raise exception 'This listing is no longer available.' using errcode = '22023';
  end if;

  update public.offers
  set state = 'accepted', accepted_at = now(),
      expires_at = now() + (private.config_for(v_listing.school_id)).offer_window
  where id = v_offer.id
  returning * into v_offer;
  update public.listings set status = 'pending' where id = v_listing.id;
  insert into private.handoff_codes (offer_id) values (v_offer.id);
  insert into public.payment_events (offer_id, kind, amount_cents) values (v_offer.id, 'authorize', v_offer.amount_cents);
  perform private.post_event(v_offer, v_uid, 'accepted', 'Accepted ' || private.money(v_offer.amount_cents));

  for v_other in select * from public.offers o where o.listing_id = v_listing.id and o.state = 'pending' order by o.id for update loop
    update public.offers set state = 'declined', ended_at = now() where id = v_other.id;
    perform private.post_event(v_other, v_uid, 'declined', 'Declined: the seller accepted another offer');
  end loop;
end;
$$;

create or replace function public.decline_offer(p_offer uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_offer public.offers := private.offer_for(v_uid, p_offer);
begin
  if v_offer.seller_id <> v_uid then
    raise exception 'Only the seller can decline an offer.' using errcode = '42501';
  end if;
  if v_offer.state <> 'pending' then
    raise exception 'This offer is already %.', v_offer.state using errcode = '22023';
  end if;
  update public.offers set state = 'declined', ended_at = now() where id = v_offer.id;
  perform private.post_event(v_offer, v_uid, 'declined', 'Declined ' || private.money(v_offer.amount_cents));
end;
$$;

create or replace function public.withdraw_offer(p_offer uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_offer public.offers := private.offer_for(v_uid, p_offer);
begin
  if v_offer.buyer_id <> v_uid then
    raise exception 'Only the buyer can withdraw an offer.' using errcode = '42501';
  end if;
  if v_offer.state <> 'pending' then
    raise exception 'This offer is already %. Accepted offers are cancelled, not withdrawn.', v_offer.state using errcode = '22023';
  end if;
  update public.offers set state = 'withdrawn', ended_at = now() where id = v_offer.id;
  perform private.post_event(v_offer, v_uid, 'withdrawn', 'Withdrew ' || private.money(v_offer.amount_cents));
end;
$$;

-- Either side, after accept. Cancels the authorization and puts the listing back.
create or replace function public.cancel_offer(p_offer uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_offer public.offers := private.offer_for(v_uid, p_offer);
begin
  if v_offer.state <> 'accepted' then
    raise exception 'Only an accepted offer can be cancelled (this one is %).', v_offer.state using errcode = '22023';
  end if;
  perform private.release_offer(v_offer, 'cancelled', v_uid,
    case when v_uid = v_offer.buyer_id then 'Buyer cancelled' else 'Seller cancelled' end);
end;
$$;

-- Buyer only: the code to show the seller, and how many seconds it has left.
create or replace function public.handoff_code(p_offer uuid)
returns table (code text, seconds_left int)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_offer public.offers;
  v_secret bytea;
begin
  select * into v_offer from public.offers o where o.id = p_offer and o.buyer_id = v_uid;
  if not found or v_uid is null then
    raise exception 'Offer not found' using errcode = 'P0002';
  end if;
  if v_offer.state <> 'accepted' or v_offer.expires_at <= now() then
    raise exception 'This offer is no longer active.' using errcode = '22023';
  end if;
  if private.is_suspended(v_uid) then
    raise exception 'Your account is suspended.' using errcode = '42501';
  end if;
  select h.secret into v_secret from private.handoff_codes h where h.offer_id = p_offer;
  return query select private.handoff_code_at(v_secret, private.handoff_window(now())),
                      (30 - floor(extract(epoch from now()))::bigint % 30)::int;
end;
$$;

-- Seller only. 'completed' on success (and again on a repeat scan), 'wrong_code' otherwise.
-- A wrong code returns instead of raising so the attempt counter commits.
create or replace function public.redeem_handoff(p_offer uuid, p_code text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_offer public.offers := private.offer_for(v_uid, p_offer);
  v_cfg public.config;
  v_hc private.handoff_codes;
  v_given text := regexp_replace(coalesce(p_code, ''), '\D', '', 'g');
  v_window bigint := private.handoff_window(now());
  v_fee int;
begin
  if v_offer.seller_id <> v_uid then
    raise exception 'Only the seller can scan the handoff code.' using errcode = '42501';
  end if;
  if v_offer.state = 'completed' then
    return 'completed';
  end if;
  if v_offer.state <> 'accepted' then
    raise exception 'This offer is %, so there is nothing to scan.', v_offer.state using errcode = '22023';
  end if;
  if v_offer.expires_at <= now() then
    raise exception 'This offer expired. The buyer wasn''t charged.' using errcode = '22023';
  end if;
  if private.blocked_between(v_offer.buyer_id, v_offer.seller_id) then
    raise exception 'This conversation has ended.' using errcode = '42501';
  end if;
  if v_offer.payment_ref is null then
    raise exception 'The buyer''s payment hold is still processing. Try again in a moment.' using errcode = '22023';
  end if;
  v_cfg := private.config_for((select l.school_id from public.listings l where l.id = v_offer.listing_id));

  select * into strict v_hc from private.handoff_codes h where h.offer_id = v_offer.id for update;
  if v_hc.total_failed >= 20 then
    raise exception 'Too many wrong codes on this offer. Cancel it and start a new one.' using errcode = '54000';
  end if;
  if v_hc.failed_since > now() - interval '10 minutes' and v_hc.failed_count >= v_cfg.handoff_max_wrong then
    raise exception 'Too many wrong codes. Wait 10 minutes and try again.' using errcode = '54000';
  end if;
  -- The current window, or the previous one for clock skew and a code read just before it turned over.
  if v_given not in (private.handoff_code_at(v_hc.secret, v_window), private.handoff_code_at(v_hc.secret, v_window - 1)) then
    update private.handoff_codes
    set total_failed = total_failed + 1,
        failed_count = case when failed_since > now() - interval '10 minutes' then failed_count + 1 else 1 end,
        failed_since = case when failed_since > now() - interval '10 minutes' then failed_since else now() end
    where offer_id = v_offer.id;
    return 'wrong_code';
  end if;

  v_fee := private.fee_cents(v_offer.amount_cents, v_cfg.fee_bps, v_cfg.fee_threshold_cents);
  insert into public.trades (offer_id, listing_id, buyer_id, seller_id, amount_cents, fee_cents)
  values (v_offer.id, v_offer.listing_id, v_offer.buyer_id, v_offer.seller_id, v_offer.amount_cents, v_fee);
  update public.offers set state = 'completed', ended_at = now() where id = v_offer.id;
  update public.listings set status = 'sold' where id = v_offer.listing_id and status = 'pending';
  if not found then
    raise exception 'This listing is no longer available.' using errcode = '22023';
  end if;
  delete from private.handoff_codes where offer_id = v_offer.id;
  insert into public.payment_events (offer_id, kind, amount_cents, fee_cents)
  values (v_offer.id, 'capture', v_offer.amount_cents, v_fee);
  perform private.post_event(v_offer, v_uid, 'completed', 'Handoff confirmed. Sold for ' || private.money(v_offer.amount_cents));
  return 'completed';
end;
$$;

-- The 4-day job: accepted offers with no scan by expires_at expire and their authorization is cancelled.
-- Idempotent; runs every minute from pg_cron. Returns how many it expired.
create or replace function private.expire_offers()
returns int
language plpgsql
set search_path = ''
as $$
declare
  v_offer public.offers;
  v_n int := 0;
begin
  for v_offer in select * from public.offers o where o.state = 'accepted' and o.expires_at <= now()
                 order by o.expires_at limit 500 for update skip locked loop
    -- One bad row must not roll back the batch and jam the job every minute.
    begin
      perform private.release_offer(v_offer, 'expired', null, 'Expired: no handoff in time. The buyer wasn''t charged.');
      v_n := v_n + 1;
    exception when others then
      raise warning 'expire_offers: offer % failed: %', v_offer.id, sqlerrm;
    end;
  end loop;
  return v_n;
end;
$$;

select cron.schedule('relist-expire-offers', '* * * * *', 'select private.expire_offers()');
select cron.schedule('relist-cron-log-cleanup', '17 3 * * *', $$delete from cron.job_run_details where end_time < now() - interval '7 days'$$);

-- Server only (secret key): the payments module reports what the provider did. Idempotent per event.
create or replace function public.payment_result(p_event bigint, p_ok boolean, p_ref text default null, p_error text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event public.payment_events;
  v_offer public.offers;
begin
  update public.payment_events
  set status = case when p_ok then 'succeeded' else 'failed' end, provider_ref = p_ref, error = left(p_error, 500),
      processed_at = now()
  where id = p_event and status = 'requested'
  returning * into v_event;
  if not found then
    return; -- already processed
  end if;
  if v_event.kind = 'authorize' and p_ok then
    update public.offers set payment_ref = p_ref where id = v_event.offer_id;
  elsif v_event.kind = 'authorize' then
    -- A failed authorization undoes the accept.
    select * into v_offer from public.offers o where o.id = v_event.offer_id and o.state = 'accepted' for update;
    if found then
      perform private.release_offer(v_offer, 'cancelled', null, 'Cancelled: the buyer''s payment didn''t go through');
    end if;
  elsif v_event.kind = 'capture' and p_ok then
    update public.trades set captured_at = now() where offer_id = v_event.offer_id;
  end if;
end;
$$;

-- Blocking ends the pair's live offers; suspension ends the user's; hiding a listing ends the listing's.
create or replace function private.end_live_offers(p_user uuid, p_other uuid, p_listing uuid default null)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_offer public.offers;
begin
  for v_offer in select * from public.offers o
                 where o.state in ('pending', 'accepted')
                   and (p_user is null or p_user in (o.buyer_id, o.seller_id))
                   and (p_other is null or p_other in (o.buyer_id, o.seller_id))
                   and (p_listing is null or o.listing_id = p_listing)
                 order by o.id for update loop
    perform private.release_offer(v_offer, 'cancelled', null, 'Cancelled: this conversation ended');
  end loop;
end;
$$;

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
  perform private.end_live_offers(v_uid, p_user);
end;
$$;

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
    -- End its live offers first (releases any hold), then take it down.
    perform private.end_live_offers(null, null, v_report.listing_id);
    update public.listings set status = 'removed' where id = v_report.listing_id;
  elsif p_action = 'suspend_user' then
    if v_report.reported_user_id is null then
      raise exception 'This report has no user.' using errcode = '22023';
    end if;
    -- Not 'infinity': Auth (Go) can't scan it and every sign-in for the user fails with a 500.
    update auth.users set banned_until = now() + interval '100 years' where id = v_report.reported_user_id;
    -- Release holds first (puts pending listings back to active), then remove everything unsold.
    perform private.end_live_offers(v_report.reported_user_id, null);
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

-- Chat: events don't count toward send limits and can't be reported; send_message never posts a handoff code.
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
      where msg.sender_id = p_uid and msg.event is null and msg.created_at > now() - interval '1 hour') >= v_cfg.msg_user_per_hour then
    raise exception 'You''re sending messages too fast. Try again later.' using errcode = '54000';
  end if;
  if (select count(*) from public.messages msg
      where msg.thread_id = p_thread and msg.sender_id = p_uid and msg.event is null
        and msg.created_at > now() - interval '1 minute') >= v_cfg.msg_thread_per_minute then
    raise exception 'Slow down a little. Try again in a minute.' using errcode = '54000';
  end if;
  return v_thread;
end;
$$;



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
  -- A handoff code is never posted. Returns null (no raise) so the rotation and strike commit.
  if private.catch_handoff_code(p_thread, v_body) then
    return null;
  end if;

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

-- report(): only real messages from the other person can be reported, not offer events.
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
    select msg.body, t.listing_id, msg.sender_id into v_quoted, v_listing, v_user
    from public.messages msg join public.threads t on t.id = msg.thread_id
    where msg.id = p_message_id and v_uid in (t.buyer_id, t.seller_id)
      and msg.sender_id <> v_uid and not msg.held and msg.event is null;
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
  if v_id is null then
    select r.id into v_id from public.reports r
    where r.reporter_id = v_uid and r.status = 'open' and r.source = 'member'
      and r.message_id is not distinct from p_message_id and r.listing_id is not distinct from v_listing
      and r.reported_user_id is not distinct from v_user;
  end if;
  return v_id;
end;
$$;

revoke execute on function public.make_offer(uuid, int), public.accept_offer(uuid), public.decline_offer(uuid),
  public.withdraw_offer(uuid), public.cancel_offer(uuid), public.handoff_code(uuid), public.redeem_handoff(uuid, text),
  public.payment_result(bigint, boolean, text, text)
  from public, anon, authenticated;
grant execute on function public.make_offer(uuid, int), public.accept_offer(uuid), public.decline_offer(uuid),
  public.withdraw_offer(uuid), public.cancel_offer(uuid), public.handoff_code(uuid), public.redeem_handoff(uuid, text)
  to authenticated;
grant execute on function public.payment_result(bigint, boolean, text, text) to service_role;
revoke execute on function private.expire_offers() from public;
