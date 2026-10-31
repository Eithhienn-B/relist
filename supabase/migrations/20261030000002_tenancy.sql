create extension if not exists postgis with schema extensions;

-- A school is an institution keyed by IPEDS UNITID, not a domain (see Tenancy research).
create table public.schools (
  id bigint primary key, -- IPEDS UNITID
  name text not null,
  short_name text not null,
  colors jsonb not null default '{}'
);

create table public.campuses (
  id bigint generated always as identity primary key,
  school_id bigint not null references public.schools on delete cascade,
  name text not null,
  location extensions.geography(point, 4326) not null,
  -- Default browse filter for members whose domain can't tell campus (purdue.edu) until campus select ships.
  is_default boolean not null default false,
  unique (school_id, name)
);
create unique index campuses_one_default_per_school on public.campuses (school_id) where is_default;
create index campuses_location_idx on public.campuses using gist (location);

-- Exact, lowercased domain -> school. No suffix or wildcard matching.
create table public.school_domains (
  domain text primary key check (domain = lower(domain) and domain like '%.edu'),
  school_id bigint not null references public.schools on delete cascade,
  evidence_url text,
  approved_at timestamptz
);
create index school_domains_school_idx on public.school_domains (school_id);

-- Written only by create_membership(). school_id is null for an unknown .edu.
create table public.memberships (
  user_id uuid primary key references auth.users on delete cascade,
  email text not null unique,
  school_id bigint references public.schools,
  campus_id bigint references public.campuses,
  grad_season text not null check (grad_season in ('spring', 'summer', 'fall')),
  grad_year smallint not null check (grad_year between 2024 and 2040),
  is_18_plus boolean not null check (is_18_plus),
  created_at timestamptz not null default now()
);
create index memberships_school_idx on public.memberships (school_id);
create index memberships_campus_idx on public.memberships (campus_id);

-- One default row (school_id null) plus optional per-school overrides.
create table public.config (
  id bigint generated always as identity primary key,
  school_id bigint unique references public.schools on delete cascade,
  fee_bps int not null default 500 check (fee_bps between 0 and 10000),
  fee_threshold_cents int not null default 1000 check (fee_threshold_cents >= 0),
  min_price_cents int not null default 500 check (min_price_cents > 0),
  listing_radius_m int not null default 8047 check (listing_radius_m > 0), -- 5 miles
  location_max_accuracy_m int not null default 500 check (location_max_accuracy_m > 0),
  location_check_ttl interval not null default '24 hours',
  offer_window interval not null default '4 days'
);
create unique index config_one_default on public.config ((school_id is null)) where school_id is null;

-- Reference data is readable by signed-in users; nothing in it is personal.
create policy "signed-in users read schools" on public.schools for select to authenticated using (true);
create policy "signed-in users read campuses" on public.campuses for select to authenticated using (true);
create policy "signed-in users read school domains" on public.school_domains for select to authenticated using (true);
create policy "signed-in users read config" on public.config for select to authenticated using (true);
create policy "members read own membership" on public.memberships for select to authenticated
  using (user_id = (select auth.uid()));

-- Clients only read these tables. Writes go through security definer functions.
revoke insert, update, delete, truncate on public.schools, public.campuses, public.school_domains,
  public.memberships, public.config from anon, authenticated;
revoke all on public.memberships from anon;

-- Seed. Coordinates are approximate campus centers; verify against IPEDS HD LATITUDE/LONGITUDE before beta.
insert into public.schools (id, name, short_name, colors) values
  (243780, 'Purdue University', 'Purdue', '{"primary": "#CFB991", "secondary": "#000000"}'),
  (151324, 'Indiana State University', 'Indiana State', '{}');

insert into public.campuses (school_id, name, location, is_default) values
  (243780, 'Indianapolis', 'SRID=4326;POINT(-86.1758 39.7743)', true),
  (243780, 'West Lafayette', 'SRID=4326;POINT(-86.9212 40.4237)', false),
  (151324, 'Terre Haute', 'SRID=4326;POINT(-87.4089 39.4703)', true);

insert into public.school_domains (domain, school_id, evidence_url, approved_at) values
  ('purdue.edu', 243780, 'https://purdue.edu/apps/account/IAMO/Purdue_CareerAccount_Eligibility.jsp', '2026-10-30'),
  ('sycamores.indstate.edu', 151324, 'https://indstate.teamdynamix.com/TDClient/1851/Portal/KB/ArticleDet?ID=97354', '2026-10-30');

insert into public.config default values;
