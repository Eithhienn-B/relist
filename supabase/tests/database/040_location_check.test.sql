-- Listing location check: every listing needs a recent, accurate device location within
-- listing_radius_m (5 mi) of a campus, and the server, never the client, picks the campus.
begin;
select plan(22);

select id as indy from public.campuses where name = 'Indianapolis' \gset
select id as wl from public.campuses where name = 'West Lafayette' \gset

-- Points due north (azimuth 0) or east (pi/2) of the Indianapolis campus, in miles.
select extensions.st_y(p::extensions.geometry) as lat_49, extensions.st_x(p::extensions.geometry) as lng_49
from (select extensions.st_project(location, 4.9 * 1609.344, 0) p from public.campuses where id = :indy) s \gset
select extensions.st_y(p::extensions.geometry) as lat_51, extensions.st_x(p::extensions.geometry) as lng_51
from (select extensions.st_project(location, 5.1 * 1609.344, 0) p from public.campuses where id = :indy) s \gset

-- A second campus 3 mi east of Indianapolis, so both are inside 5 mi of points between them.
insert into public.campuses (school_id, name, location)
select 151324, 'Test East', extensions.st_project(location, 3 * 1609.344, pi() / 2) from public.campuses where id = :indy
returning id as east \gset
select extensions.st_y(p::extensions.geometry) as lat_e2, extensions.st_x(p::extensions.geometry) as lng_e2
from (select extensions.st_project(location, 2 * 1609.344, pi() / 2) p from public.campuses where id = :indy) s \gset
select extensions.st_y(p::extensions.geometry) as lat_e05, extensions.st_x(p::extensions.geometry) as lng_e05
from (select extensions.st_project(location, 0.5 * 1609.344, pi() / 2) p from public.campuses where id = :indy) s \gset

select tests.create_user('alice@purdue.edu') as alice \gset
select tests.create_user('bob@purdue.edu') as bob \gset
select tests.create_user('dave@purdue.edu') as dave \gset
select tests.create_user('erin@purdue.edu') as erin \gset
select tests.create_user('nomember@purdue.edu') as nomember \gset
insert into public.memberships (user_id, email, school_id, campus_id, grad_season, grad_year, is_18_plus) values
  (:'alice', 'alice@purdue.edu', 243780, :indy, 'spring', 2029, true),
  (:'bob', 'bob@purdue.edu', 243780, :indy, 'spring', 2029, true),
  (:'dave', 'dave@purdue.edu', 243780, :indy, 'spring', 2029, true),
  (:'erin', 'erin@purdue.edu', 243780, :indy, 'spring', 2029, true);

-- Dave passed a check 25 hours ago; Erin has used up her hourly checks.
insert into public.location_checks (user_id, campus_id, passed, accuracy_m, checked_at)
values (:'dave', :indy, true, 20, now() - interval '25 hours');
insert into public.location_checks (user_id, passed, reason, accuracy_m)
select :'erin', false, 'too_far', 20 from generate_series(1, 30);

-- The function has no way to receive a campus from the client.
select is_empty(
  $$ select 1 from pg_proc where proname = 'create_listing' and array_to_string(proargnames, ',') ilike '%campus%' $$,
  'create_listing takes no campus argument'
);

select tests.authenticate_as(:'alice');

select is(
  (select passed from public.check_location(:lat_49, :lng_49, 20)), true, '4.9 mi from campus passes'
);
select is(
  (select campus_id from public.location_checks where user_id = :'alice' order by id desc limit 1), :indy::bigint,
  'a passing check is tagged with the campus'
);
select results_eq(
  format('select passed, reason, campus_id from public.check_location(%s, %s, 20)', :lat_51, :lng_51),
  $$ values (false, 'too_far'::text, null::bigint) $$,
  '5.1 mi from campus fails'
);
select results_eq(
  format('select passed, reason from public.check_location(%s, %s, 600)', :lat_49, :lng_49),
  $$ values (false, 'low_accuracy'::text) $$,
  'accuracy worse than location_max_accuracy_m fails, even in range'
);
select is(
  (select campus_id from public.check_location(:lat_e2, :lng_e2, 20)), :east::bigint,
  'the nearer of two in-range campuses wins (2 mi vs 1 mi)'
);
select is(
  (select campus_id from public.check_location(:lat_e05, :lng_e05, 20)), :indy::bigint,
  'the nearer of two in-range campuses wins (0.5 mi vs 2.5 mi)'
);
select throws_ok(
  'select * from public.check_location(91, 0, 20)', '22023', null, 'impossible coordinates are rejected'
);

-- Alice's latest passing check was 0.5 mi east, so her listing lands on Indianapolis.
select is(
  (select campus_id from public.create_listing('Desk lamp', 'Works fine', 1500, 'decor')), :indy::bigint,
  'the listing campus comes from the latest passing check'
);
select is(
  (select school_id from public.listings where seller_id = :'alice'), 243780::bigint,
  'the listing carries the seller''s school'
);
select throws_ok(
  format($$ insert into public.listings (seller_id, campus_id, title, price_cents, category)
            values (%L, %s, 'Sneaky', 1500, 'other') $$, :'alice', :wl),
  '42501', null, 'a client cannot insert a listing with its own campus_id'
);
select throws_ok(
  format('update public.listings set campus_id = %s', :wl),
  '42501', null, 'a client cannot move a listing to another campus'
);
select throws_ok(
  $$ select public.create_listing('Cheap thing', '', 499, 'other') $$,
  '22023', null, 'price under min_price_cents is rejected'
);
select throws_ok(
  $$ select public.create_listing('Disposable vape, barely used', '', 1500, 'other') $$,
  '22023', null, 'a prohibited item is rejected'
);
select throws_ok(
  $$ select public.create_listing('Graco infant car seat', '', 4000, 'other') $$,
  '22023', null, 'a recall-prone item (car seat) is rejected'
);
select lives_ok(
  $$ select public.create_listing('Gundam model kit', 'Begun but not finished', 2500, 'other') $$,
  'prohibited terms match whole words only ("gun" does not block "Gundam" or "begun")'
);

-- Bob is from Alice's school with Indianapolis as home campus, and still has to check.
select tests.authenticate_as(:'bob');
select throws_ok(
  $$ select public.create_listing('Mini fridge', '', 6000, 'kitchen') $$,
  '22023', null, 'your own school''s campus still needs a location check'
);

select tests.authenticate_as(:'dave');
select throws_ok(
  $$ select public.create_listing('Mini fridge', '', 6000, 'kitchen') $$,
  '22023', null, 'a check older than location_check_ttl has expired'
);

select tests.authenticate_as(:'erin');
select throws_ok(
  format('select * from public.check_location(%s, %s, 20)', :lat_49, :lng_49),
  '54000', null, 'location checks are rate limited per user'
);

select tests.authenticate_as(:'nomember');
select throws_ok(
  format('select * from public.check_location(%s, %s, 20)', :lat_49, :lng_49),
  '42501', null, 'a signed-in user without a membership cannot check location'
);

reset role;

-- No coordinates stored anywhere: the only spatial column in the database is campuses.location,
-- no column is named like a coordinate, and no stored check contains the coordinates sent.
select is_empty(
  $$ select table_schema || '.' || table_name || '.' || column_name from information_schema.columns
     where table_schema not in ('pg_catalog', 'information_schema', 'extensions')
       and (udt_name in ('geography', 'geometry', 'point')
            or column_name ~* '(^|_)(lat|lng|lon|latitude|longitude|coords?)($|_)')
       and not (table_schema = 'public' and table_name = 'campuses' and column_name = 'location') $$,
  'no spatial or coordinate-named column exists outside campuses.location'
);
select is_empty(
  format($$ select 1 from public.location_checks lc
            where strpos(to_jsonb(lc)::text, %L) > 0 or strpos(to_jsonb(lc)::text, %L) > 0 $$,
         left(:'lat_49', 7), left(:'lng_e05', 8)),
  'stored location checks contain none of the coordinates that were sent'
);

select * from finish();
rollback;
