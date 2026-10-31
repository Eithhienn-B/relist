-- M1: listings, location checks, photos, prohibited items.

-- The config that applies to a school: its override row, else the default row.
create or replace function private.config_for(p_school_id bigint)
returns public.config
language sql
stable
set search_path = ''
as $$
  select * from public.config c
  where c.school_id = p_school_id or c.school_id is null
  order by c.school_id nulls last
  limit 1;
$$;

-- One row per location check. Stores the outcome only, never coordinates (Decision 6).
create table public.location_checks (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users on delete cascade,
  campus_id bigint references public.campuses on delete cascade,
  passed boolean not null,
  reason text check (reason in ('too_far', 'low_accuracy')),
  accuracy_m real not null check (accuracy_m >= 0),
  checked_at timestamptz not null default now(),
  check (passed = (reason is null) and passed = (campus_id is not null))
);
create index location_checks_user_idx on public.location_checks (user_id, checked_at desc);
create index location_checks_campus_idx on public.location_checks (campus_id);

create table public.listings (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references auth.users on delete cascade,
  school_id bigint references public.schools, -- seller's school when listed; null for an unknown .edu
  campus_id bigint not null references public.campuses, -- set by create_listing() from the location check
  title text not null check (char_length(title) between 3 and 80),
  description text not null default '' check (char_length(description) <= 2000),
  price_cents int not null check (price_cents between 1 and 1000000),
  category text not null check (category in
    ('furniture', 'electronics', 'textbooks', 'clothing', 'kitchen', 'decor', 'sports', 'other')),
  status text not null default 'active' check (status in ('active', 'pending', 'sold', 'removed')),
  created_at timestamptz not null default now(),
  search tsvector generated always as
    (to_tsvector('english'::regconfig, title || ' ' || description)) stored
);
create index listings_browse_idx on public.listings (campus_id, created_at desc) where status = 'active';
create index listings_newest_idx on public.listings (created_at desc) where status = 'active';
create index listings_search_idx on public.listings using gin (search);
create index listings_seller_idx on public.listings (seller_id, created_at desc);
create index listings_school_idx on public.listings (school_id);

create table public.listing_photos (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings on delete cascade,
  path text not null unique, -- object name in the listing-photos bucket: {listing_id}/{uuid}.webp
  position smallint not null default 0,
  moderation text not null check (moderation in ('approved', 'held')),
  flags text[] not null default '{}', -- moderation categories that fired, for the review queue
  created_at timestamptz not null default now()
);
create index listing_photos_listing_idx on public.listing_photos (listing_id, position);

-- Verified student = has a membership row. Own-row RLS on memberships makes this safe as invoker.
create policy "members see active listings and their own" on public.listings for select to authenticated
  using (
    seller_id = (select auth.uid())
    or (status = 'active' and exists (select 1 from public.memberships m where m.user_id = (select auth.uid())))
  );
-- Visibility follows the listing's RLS; held photos are visible to the seller only.
create policy "members see approved photos of visible listings" on public.listing_photos for select to authenticated
  using (exists (
    select 1 from public.listings l
    where l.id = listing_id and (moderation = 'approved' or l.seller_id = (select auth.uid()))
  ));
create policy "users see their own location checks" on public.location_checks for select to authenticated
  using (user_id = (select auth.uid()));

-- Read only for clients. Rows are written by create_listing(), check_location() and the upload
-- server action (secret key, after EXIF strip + moderation).
revoke all on public.listings, public.listing_photos, public.location_checks from anon, authenticated;
grant select on public.listings, public.location_checks to authenticated;
-- Column grant: sellers see that a photo is held, not which moderation categories fired.
grant select (id, listing_id, path, position, moderation, created_at) on public.listing_photos to authenticated;

-- Photo bucket: private, webp only (the server re-encodes every upload). No client write policies.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('listing-photos', 'listing-photos', false, 2097152, '{image/webp}');

create policy "members read photos they can see" on storage.objects for select to authenticated
  using (
    bucket_id = 'listing-photos'
    and exists (select 1 from public.listing_photos p where p.path = objects.name)
  );

-- Prohibited items. Terms are whole words after lowercasing and turning punctuation into spaces.
create table private.prohibited_terms (
  term text primary key check (term = lower(term) and term ~ '^[a-z0-9]+( [a-z0-9]+)*$'),
  reason text not null
);

insert into private.prohibited_terms (term, reason)
select t, r from (values
  ('Alcohol isn''t allowed on ReList.',
   array['alcohol', 'beer', 'wine', 'liquor', 'vodka', 'whiskey', 'tequila', 'rum']),
  ('Tobacco, nicotine and vapes aren''t allowed on ReList.',
   array['vape', 'vapes', 'vaping', 'juul', 'cigarette', 'cigarettes', 'cigar', 'cigars', 'tobacco', 'nicotine', 'zyn', 'hookah']),
  ('Drugs, cannabis and prescription medicine aren''t allowed on ReList.',
   array['weed', 'cannabis', 'marijuana', 'thc', 'delta 8', 'kratom', 'adderall', 'xanax', 'oxy', 'prescription', 'insulin']),
  ('Weapons, ammunition and fireworks aren''t allowed on ReList.',
   array['gun', 'guns', 'firearm', 'pistol', 'rifle', 'shotgun', 'ammo', 'ammunition', 'taser', 'brass knuckles', 'switchblade', 'fireworks']),
  ('Cribs, infant sleepers, car seats and helmets are often recalled and can''t be checked here, so they aren''t allowed. See cpsc.gov/Recalls.',
   array['crib', 'cribs', 'bassinet', 'infant sleeper', 'rock n play', 'car seat', 'car seats', 'helmet', 'helmets']),
  ('Used underwear and swimwear aren''t allowed on ReList.',
   array['underwear', 'panties', 'lingerie', 'swimsuit', 'bikini']),
  ('Animals can''t be sold on ReList.',
   array['puppy', 'puppies', 'kitten', 'kittens', 'live animal']),
  ('Gift cards, access codes and accounts aren''t allowed on ReList.',
   array['gift card', 'gift cards', 'access code', 'netflix account', 'spotify account']),
  ('Exam answers and assignments break academic integrity rules.',
   array['test bank', 'answer key', 'exam answers', 'homework answers', 'essay writing']),
  ('Counterfeit and adult items aren''t allowed on ReList.',
   array['counterfeit', 'replica', 'porn', 'sex toy', 'onlyfans'])
) as v(r, terms), unnest(v.terms) as t;

create or replace function private.prohibited_reason(p_text text)
returns text
language sql
stable
set search_path = ''
as $$
  select p.reason from private.prohibited_terms p
  where ' ' || regexp_replace(lower(p_text), '[^a-z0-9]+', ' ', 'g') || ' ' like '% ' || p.term || ' %'
  limit 1;
$$;

-- Browser sends its location; the server picks the nearest campus within listing_radius_m and
-- stores pass/fail, campus and accuracy. The coordinates exist only for this call.
create or replace function public.check_location(p_lat double precision, p_lng double precision, p_accuracy_m double precision)
returns table (passed boolean, reason text, campus_id bigint, campus_name text, school_name text, expires_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid uuid := (select auth.uid());
  v_cfg public.config;
  v_point extensions.geography;
  v_campus_id bigint;
  v_reason text;
  v_check public.location_checks;
begin
  if not exists (select 1 from public.memberships m where m.user_id = v_uid) then
    raise exception 'Finish sign-up first' using errcode = '42501';
  end if;
  if p_lat is null or p_lng is null or p_accuracy_m is null
     or p_lat not between -90 and 90 or p_lng not between -180 and 180 or p_accuracy_m < 0 then
    raise exception 'That location doesn''t look right. Try again.' using errcode = '22023';
  end if;
  -- Serialize per user so parallel calls can't all pass the count below.
  perform pg_advisory_xact_lock(hashtextextended('location_checks:' || v_uid::text, 0));
  -- Keep only a week of history; a check is only useful for location_check_ttl anyway.
  delete from public.location_checks lc where lc.user_id = v_uid and lc.checked_at < now() - interval '7 days';
  if (select count(*) from public.location_checks lc
      where lc.user_id = v_uid and lc.checked_at > now() - interval '1 hour') >= 30 then
    raise exception 'Too many location checks. Try again in an hour.' using errcode = '54000';
  end if;

  select * into v_cfg from private.config_for((select m.school_id from public.memberships m where m.user_id = v_uid));

  if p_accuracy_m > v_cfg.location_max_accuracy_m then
    v_reason := 'low_accuracy';
  else
    v_point := extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography;
    select c.id into v_campus_id
    from public.campuses c
    where extensions.st_dwithin(c.location, v_point, v_cfg.listing_radius_m)
    order by extensions.st_distance(c.location, v_point)
    limit 1;
    if v_campus_id is null then
      v_reason := 'too_far';
    end if;
  end if;

  insert into public.location_checks (user_id, campus_id, passed, reason, accuracy_m)
  values (v_uid, v_campus_id, v_reason is null, v_reason, p_accuracy_m)
  returning * into v_check;

  return query
    select v_check.passed, v_check.reason, c.id, c.name, s.short_name, v_check.checked_at + v_cfg.location_check_ttl
    from (select 1) one
    left join public.campuses c on c.id = v_check.campus_id
    left join public.schools s on s.id = c.school_id;
end;
$$;

-- campus_id is deliberately not a parameter: the listing goes on the campus of the seller's
-- latest passing check inside location_check_ttl.
create or replace function public.create_listing(p_title text, p_description text, p_price_cents int, p_category text)
returns public.listings
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_school_id bigint;
  v_cfg public.config;
  v_campus_id bigint;
  v_reason text;
  v_listing public.listings;
begin
  select m.school_id into v_school_id from public.memberships m where m.user_id = v_uid;
  if not found then
    raise exception 'Finish sign-up first' using errcode = '42501';
  end if;
  v_cfg := private.config_for(v_school_id);

  select lc.campus_id into v_campus_id
  from public.location_checks lc
  where lc.user_id = v_uid and lc.passed and lc.checked_at > now() - v_cfg.location_check_ttl
  order by lc.checked_at desc, lc.id desc
  limit 1;
  if v_campus_id is null then
    raise exception 'Check your location first. You need to be within 5 miles of a campus to list.'
      using errcode = '22023';
  end if;

  if p_price_cents is null or p_price_cents < v_cfg.min_price_cents then
    raise exception 'The minimum price is $%.', to_char(v_cfg.min_price_cents / 100.0, 'FM999990.00')
      using errcode = '22023';
  end if;
  v_reason := private.prohibited_reason(coalesce(p_title, '') || ' ' || coalesce(p_description, ''));
  if v_reason is not null then
    raise exception '%', v_reason using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('listings:' || v_uid::text, 0));
  if (select count(*) from public.listings l where l.seller_id = v_uid and l.created_at > now() - interval '1 day') >= 20 then
    raise exception 'You''ve hit today''s listing limit (20).' using errcode = '54000';
  end if;

  insert into public.listings (seller_id, school_id, campus_id, title, description, price_cents, category)
  values (v_uid, v_school_id, v_campus_id, trim(p_title), trim(coalesce(p_description, '')), p_price_cents, p_category)
  returning * into v_listing;
  return v_listing;
end;
$$;

-- "Near me" browse filter: the campus nearest a point. Nothing is stored.
create or replace function public.nearest_campus(p_lat double precision, p_lng double precision)
returns bigint
language sql
stable
set search_path = ''
as $$
  select c.id from public.campuses c
  where exists (select 1 from public.memberships m where m.user_id = (select auth.uid()))
  order by c.location operator(extensions.<->)
    extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography
  limit 1;
$$;

revoke execute on function public.check_location(double precision, double precision, double precision),
  public.create_listing(text, text, int, text),
  public.nearest_campus(double precision, double precision) from public, anon;
grant execute on function public.check_location(double precision, double precision, double precision),
  public.create_listing(text, text, int, text),
  public.nearest_campus(double precision, double precision) to authenticated;
