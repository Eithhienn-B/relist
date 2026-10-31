-- Privacy suite, listings: listings, listing_photos, location_checks and the listing-photos bucket.
begin;
select plan(24);

select id as indy from public.campuses where name = 'Indianapolis' \gset

select tests.create_user('alice@purdue.edu') as alice \gset
select tests.create_user('bob@sycamores.indstate.edu') as bob \gset
-- Mallory has a verified email but never finished sign-up.
select tests.create_user('mallory@purdue.edu') as mallory \gset
insert into public.memberships (user_id, email, school_id, campus_id, grad_season, grad_year, is_18_plus) values
  (:'alice', 'alice@purdue.edu', 243780, :indy, 'spring', 2029, true),
  (:'bob', 'bob@sycamores.indstate.edu', 151324, null, 'fall', 2028, true);

-- Alice: one active listing with an approved and a held photo, and one removed listing.
insert into public.listings (seller_id, school_id, campus_id, title, price_cents, category)
values (:'alice', 243780, :indy, 'Desk lamp', 1500, 'decor') returning id as active \gset
insert into public.listings (seller_id, school_id, campus_id, title, price_cents, category, status)
values (:'alice', 243780, :indy, 'Old chair', 1500, 'furniture', 'removed') returning id as removed \gset
insert into public.listing_photos (listing_id, path, moderation) values
  (:'active', :'active' || '/ok.webp', 'approved'),
  (:'active', :'active' || '/held.webp', 'held'),
  (:'removed', :'removed' || '/old.webp', 'approved');
insert into storage.objects (bucket_id, name) values
  ('listing-photos', :'active' || '/ok.webp'),
  ('listing-photos', :'active' || '/held.webp'),
  ('listing-photos', :'removed' || '/old.webp'),
  ('listing-photos', 'orphan/no-row.webp');
insert into public.location_checks (user_id, campus_id, passed, accuracy_m) values (:'alice', :indy, true, 15);

-- Bob: a member from another school. One shared marketplace, so he sees Alice's active listing.
select tests.authenticate_as(:'bob');
select results_eq('select id from public.listings', format('values (%L::uuid)', :'active'),
  'a member from another school sees active listings only');
select results_eq('select path from public.listing_photos', format('values (%L)', :'active' || '/ok.webp'),
  'a member sees approved photos of active listings only');
select results_eq($$ select name from storage.objects where bucket_id = 'listing-photos' $$,
  format('values (%L)', :'active' || '/ok.webp'),
  'a member can read only approved photo objects of active listings');
select is_empty('select 1 from public.location_checks', 'a member cannot see another user''s location checks');
select throws_ok(
  format($$ insert into public.listings (seller_id, campus_id, title, price_cents, category)
            values (%L, %s, 'Spam', 1500, 'other') $$, :'bob', :indy),
  '42501', null, 'a member cannot insert listings directly');
select throws_ok(format($$ update public.listings set price_cents = 1 where id = %L $$, :'active'),
  '42501', null, 'a member cannot update someone else''s listing');
select throws_ok('delete from public.listings', '42501', null, 'a member cannot delete listings');
select throws_ok(
  format($$ insert into public.listing_photos (listing_id, path, moderation) values (%L, 'x.webp', 'approved') $$, :'active'),
  '42501', null, 'a member cannot add or approve photos');
select throws_ok($$ update public.listing_photos set moderation = 'approved' $$,
  '42501', null, 'a member cannot un-hold a photo');
select throws_ok(
  format($$ insert into public.location_checks (user_id, campus_id, passed, accuracy_m) values (%L, %s, true, 5) $$, :'bob', :indy),
  '42501', null, 'a member cannot forge a passing location check');
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('listing-photos', 'bob/raw.jpg') $$,
  '42501', null, 'a member cannot upload to the photo bucket directly (EXIF strip and moderation are server-side)');
-- The Storage API sets this flag and then deletes under the caller's RLS; do the same.
select set_config('storage.allow_delete_query', 'true', true);
select is_empty(
  format($$ with d as (delete from storage.objects where name = %L returning 1) select * from d $$, :'active' || '/ok.webp'),
  'a member cannot delete photo objects');
select is_empty(
  $$ with u as (update storage.objects set name = 'stolen.webp' where bucket_id = 'listing-photos' returning 1) select * from u $$,
  'a member cannot rename photo objects');

-- Alice: the seller sees her own listings and held photos.
select tests.authenticate_as(:'alice');
select set_eq('select id from public.listings', format('values (%L::uuid), (%L::uuid)', :'active', :'removed'),
  'a seller sees their own listings, including removed ones');
select ok(
  (select count(*) = 3 from public.listing_photos),
  'a seller sees their own held photos');
select is((select count(*)::int from public.location_checks), 1, 'a user sees their own location checks');
select throws_ok(format($$ update public.listings set status = 'active' where id = %L $$, :'removed'),
  '42501', null, 'a seller cannot write their listing row directly');

-- Mallory: signed in, verified email, but no membership.
select tests.authenticate_as(:'mallory');
select is_empty('select 1 from public.listings', 'a non-member sees no listings');
select is_empty('select 1 from public.listing_photos', 'a non-member sees no photos');
select is_empty($$ select 1 from storage.objects where bucket_id = 'listing-photos' $$,
  'a non-member can read no photo objects');

-- Anonymous
select tests.authenticate_as_anon();
select throws_ok('select * from public.listings', '42501', null, 'anon cannot query listings');
select throws_ok('select * from public.listing_photos', '42501', null, 'anon cannot query listing photos');
select throws_ok('select * from public.location_checks', '42501', null, 'anon cannot query location checks');
select is_empty($$ select 1 from storage.objects where bucket_id = 'listing-photos' $$,
  'anon can read no photo objects');

select * from finish();
rollback;
