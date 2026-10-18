-- End-to-end checks for the Third Place schema, run against plain Postgres with the auth stub.
-- Any failed assert stops the run (psql ON_ERROR_STOP).

\set ON_ERROR_STOP on
set client_min_messages = warning;

-- ---------------------------------------------------------------------------
-- Cast
-- ---------------------------------------------------------------------------
create temp table cast_ids (name text primary key, id uuid);
insert into cast_ids values
  ('me',        '00000000-0000-0000-0000-00000000000a'),
  ('maya',      '00000000-0000-0000-0000-00000000000b'),
  ('jonah',     '00000000-0000-0000-0000-00000000000c'),
  ('parkperson','00000000-0000-0000-0000-00000000000d'),
  ('festival',  '00000000-0000-0000-0000-00000000000e'),
  ('wrongpref', '00000000-0000-0000-0000-00000000000f'),
  ('blocked',   '00000000-0000-0000-0000-000000000010'),
  ('friends',   '00000000-0000-0000-0000-000000000011'),
  ('syncer',    '00000000-0000-0000-0000-000000000012');
insert into cast_ids
select 'parkfan' || i, ('00000000-0000-0000-0000-0000000001' || lpad(i::text, 2, '0'))::uuid
from generate_series(1, 8) i;

create temp table spot (name text primary key, cell text);
insert into spot values
  ('cafe',   tp_private.geohash_encode(51.5450, -0.0553)),
  ('gym',    tp_private.geohash_encode(51.5270, -0.0550)),
  ('park',   tp_private.geohash_encode(51.5362, -0.0402)),
  ('home',   tp_private.geohash_encode(51.5560, -0.0560)),
  ('glasto', tp_private.geohash_encode(51.1550, -2.5850));

insert into auth.users select id from cast_ids;

insert into public.profiles (id, first_name, birthday, gender, show_me, intent)
select id,
       initcap(name),
       date '1996-05-01',
       case when name in ('jonah', 'festival', 'wrongpref') then 'man' else 'woman' end,
       case when name = 'jonah' then 'women' when name = 'wrongpref' then 'men' else 'everyone' end,
       case when name = 'friends' then 'friends' when name = 'festival' then 'both' else 'dating' end
from cast_ids;

grant select on cast_ids, spot to anon, authenticated;

-- Places (the peak cell is the place key; one-cell clusters keep the test readable).

insert into public.places (user_id, place_key, cells, category, neighbourhood, venue_name, rhythm, visit_days)
select c.id, s.cell, array[s.cell], v.category, v.hood, v.venue, v.rhythm, v.days
from (values
  ('me',         'cafe', 'Café',         'Hackney',        'Little Fern Coffee', 'Tue and Thu mornings', 40),
  ('me',         'gym',  'Climbing gym', 'Bethnal Green',  'Blocworks',          'Thursday evenings',    20),
  ('me',         'park', 'Park',         'Tower Hamlets',  'Victoria Park',      'Sunday mornings',      10),
  ('maya',       'cafe', 'Café',         'Hackney',        'Little Fern',        'Weekday mornings',     30),
  ('jonah',      'gym',  'Climbing gym', 'Bethnal Green',  'Blocworks Climbing', 'Thursday evenings',     2),
  ('parkperson', 'park', 'Park',         'Tower Hamlets',  'Victoria Park',      'Sunday afternoons',    21),
  ('wrongpref',  'cafe', 'Café',         'Hackney',        'Little Fern',        'Weekday mornings',     12),
  ('blocked',    'cafe', 'Café',         'Hackney',        'Little Fern',        'Weekday mornings',     12),
  ('friends',    'cafe', 'Café',         'Hackney',        'Little Fern',        'Weekday mornings',     12)
) as v(who, spot, category, hood, venue, rhythm, days)
join cast_ids c on c.name = v.who
join spot s on s.name = v.spot;

insert into public.places (user_id, place_key, cells, category, neighbourhood, venue_name, rhythm, visit_days)
select c.id, s.cell, array[s.cell], 'Park', 'Tower Hamlets', 'Victoria Park', 'Weekends', 5
from cast_ids c, spot s where c.name like 'parkfan%' and s.name = 'park';

insert into public.moments (user_id, moment_key, area5, title, starts_on, ends_on)
select c.id, 'glasto', left(s.cell, 5), 'Pilton', (now() - interval '120 days')::date, (now() - interval '118 days')::date
from cast_ids c, spot s where c.name in ('me', 'festival') and s.name = 'glasto';

-- Presence helpers: hour h on weekday d (0 = Monday) of the week w weeks ago.
create temp table presence_plan (who text, spot text, weeks int[], weekday int, hour int);
insert into presence_plan values
  ('me',         'cafe', array(select generate_series(1, 40)), 1, 8),
  ('me',         'cafe', array(select generate_series(1, 40)), 3, 8),
  ('maya',       'cafe', array(select generate_series(1, 30)), 1, 8),
  ('me',         'gym',  array(select generate_series(1, 20)), 3, 19),
  ('jonah',      'gym',  array[3, 4],                          3, 20),
  ('me',         'park', array(select generate_series(1, 10)), 6, 10),
  ('parkperson', 'park', array(select generate_series(20, 40)), 6, 15);

insert into public.presence (user_id, area, hour)
select c.id, s.cell,
       date_trunc('week', now()) - make_interval(weeks => w) + make_interval(days => pp.weekday, hours => pp.hour)
from presence_plan pp
join cast_ids c on c.name = pp.who
join spot s on s.name = pp.spot
cross join unnest(pp.weeks) w;

insert into public.presence (user_id, area, hour)
select c.id, s.cell, date_trunc('day', now() - interval '119 days') + interval '21 hours'
from cast_ids c, spot s where c.name in ('me', 'festival') and s.name = 'glasto';

insert into public.blocks (blocker, blocked)
select (select id from cast_ids where name = 'me'), (select id from cast_ids where name = 'blocked');

-- ---------------------------------------------------------------------------
-- The feed, as me
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', (select id::text from cast_ids where name = 'me'), false);
set role authenticated;
create temp table feed as
  select f.ordinality as rank, f.person_id, f.first_name, f.score, f.crossings, c.name
  from public.get_feed(50) with ordinality f join cast_ids c on c.id = f.person_id;
reset role;

do $$
declare
  r record;
begin
  for r in select rank, name, round(score::numeric, 3) as score, crossings->0->>'tier' as tier from feed order by rank loop
    raise warning 'feed %: % (score %, %)', r.rank, r.name, r.score, r.tier;
  end loop;

  assert not exists (select 1 from feed a join feed b on b.rank = a.rank + 1 where b.score > a.score),
    'the feed is sorted by score';
  assert (select name from feed where rank = 1) = 'maya', 'Maya shares my #1 café and the same hours, so she leads';
  assert (select rank from feed where name = 'jonah') < (select rank from feed where name = 'parkperson'),
    'a shared climbing gym beats a shared popular park';
  assert exists (select 1 from feed where name = 'festival' and crossings @> '[{"kind": "moment"}]'),
    'someone from the same festival hour shows up via a moment';
  assert not exists (select 1 from feed where name in ('wrongpref', 'blocked', 'friends', 'me')),
    'preferences, blocks and intent are respected';

  assert (select crossings->0->>'tier' from feed where name = 'maya') = 'regulars', 'Maya is a regular';
  assert (select (crossings->0->>'weeks_in_common')::int from feed where name = 'maya') >= 25, 'weeks in common counted';
  assert (select crossings->0->>'tier' from feed where name = 'jonah') = 'near_miss', 'Jonah missed me by an hour';
  assert (select crossings->0->>'tier' from feed where name = 'parkperson') = 'same_place', 'same park, never the same day';
  assert (select crossings->0->>'category' from feed where name = 'maya') = 'Café', 'category is shown';
  assert not (select crossings::text from feed where name = 'maya') like '%Little Fern%', 'venue name stays hidden before a match';
  assert (select score from feed where name = 'maya') <= 1, 'score is capped at 1';
end $$;

-- ---------------------------------------------------------------------------
-- Privacy: row level security and the presence guard
-- ---------------------------------------------------------------------------
set role authenticated;
do $$
begin
  assert (select count(*) from public.profiles) = 1, 'I can only read my own profile';
  assert (select count(*) from public.presence where user_id <> auth.uid()) = 0, 'no one else''s presence is visible';
  assert (select count(*) from public.places where user_id <> auth.uid()) = 0, 'no one else''s places are visible';

  begin
    insert into public.presence (user_id, area, hour)
    values (auth.uid(), (select cell from spot where name = 'home'), date_trunc('hour', now() - interval '1 day'));
    assert false, 'presence at home must be rejected';
  exception when raise_exception then null;
  end;

  begin
    insert into public.likes (from_user, to_user, item) values (auth.uid(), '00000000-0000-0000-0000-00000000000b', 'first');
    assert false, 'likes can only be sent through like_person()';
  exception when insufficient_privilege then null;
  end;

  update public.profiles set verified = true, is_demo = true where id = auth.uid();
  assert not (select verified or is_demo from public.profiles where id = auth.uid()), 'users can''t verify themselves';
end $$;
reset role;

-- ---------------------------------------------------------------------------
-- Before sign-up: counts only, never fewer than 2
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', '', false);
set role anon;
do $$
declare
  preview jsonb;
begin
  preview := public.preview_overlaps(jsonb_build_array(
    jsonb_build_object('key', 'cafe', 'cells', jsonb_build_array((select cell from spot where name = 'cafe'))),
    jsonb_build_object('key', 'glasto', 'cells', jsonb_build_array((select cell from spot where name = 'glasto')))));
  assert (preview->'places'->>'cafe')::int >= 2, 'the café count is shown';
  assert (preview->'places'->>'glasto')::int = 0, 'a place with fewer than 2 people reports 0';
  assert (preview->>'total')::int = (preview->'places'->>'cafe')::int, 'total counts distinct people';

  begin
    perform public.get_feed(5);
    assert false, 'the feed needs an account';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- ---------------------------------------------------------------------------
-- Syncing: rows outside kept places are dropped, and the whole set is replaced
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', (select id::text from cast_ids where name = 'syncer'), false);
set role authenticated;
do $$
declare
  result jsonb;
  cafe text := (select cell from spot where name = 'cafe');
  home text := (select cell from spot where name = 'home');
begin
  result := public.sync_my_places(
    jsonb_build_array(jsonb_build_object('place_key', cafe, 'cells', jsonb_build_array(cafe), 'category', 'Café',
                                         'neighbourhood', 'Hackney', 'venue_name', 'Little Fern', 'rhythm', 'Mornings', 'visit_days', 3)),
    '[]'::jsonb,
    jsonb_build_array(
      jsonb_build_object('area', cafe, 'hour', now() - interval '2 days'),
      jsonb_build_object('area', cafe, 'hour', now() - interval '9 days'),
      jsonb_build_object('area', home, 'hour', now() - interval '2 days')));
  assert (result->>'presence')::int = 2, 'home presence was dropped, café presence kept';
  assert (select count(*) from public.presence) = 2, 'stored presence matches';

  result := public.sync_my_places('[]'::jsonb, '[]'::jsonb, '[]'::jsonb);
  assert (select count(*) from public.places) = 0 and (select count(*) from public.presence) = 0, 'sync replaces everything';
end $$;
reset role;

-- ---------------------------------------------------------------------------
-- Likes, matches and the daily limit
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', (select id::text from cast_ids where name = 'maya'), false);
set role authenticated;
select public.like_person('00000000-0000-0000-0000-00000000000a', 'first', 'Same café!');
reset role;

select set_config('request.jwt.claim.sub', (select id::text from cast_ids where name = 'me'), false);
set role authenticated;
do $$
declare
  result jsonb;
  fan uuid;
  i int := 0;
begin
  result := public.like_person('00000000-0000-0000-0000-00000000000b', 'photo1');
  assert (result->>'matched')::boolean, 'a mutual like is a match';
  assert (result->>'likes_left')::int = 7, 'one like used';

  assert exists (
    select 1 from public.get_matches() m
    where m.first_name = 'Maya' and m.shared_places @> '[{"my_venue": "Little Fern Coffee", "their_venue": "Little Fern"}]'),
    'after a match, the exact venue is revealed';
  assert not exists (select 1 from public.get_feed(50) where person_id = '00000000-0000-0000-0000-00000000000b'),
    'matched people leave the feed';

  for fan in select id from cast_ids where name like 'parkfan%' order by name loop
    i := i + 1;
    result := public.like_person(fan, 'first');
    if i <= 7 then
      assert (result->>'ok')::boolean, format('like %s goes through', i);
    else
      assert not (result->>'ok')::boolean and result->>'reason' = 'out_of_likes', 'the 9th like of the day is refused';
    end if;
  end loop;
  assert public.likes_left() = 0, 'no likes left';

  perform public.pass_person('00000000-0000-0000-0000-00000000000d');
  assert not exists (select 1 from public.get_feed(50) where person_id = '00000000-0000-0000-0000-00000000000d'),
    'passed people leave the feed';
end $$;
reset role;

-- ---------------------------------------------------------------------------
-- Leaving: everything goes
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', (select id::text from cast_ids where name = 'me'), false);
set role authenticated;
select public.delete_my_account();
reset role;

do $$
declare
  me uuid := '00000000-0000-0000-0000-00000000000a';
begin
  assert not exists (select 1 from public.profiles where id = me), 'profile deleted';
  assert not exists (select 1 from public.presence where user_id = me), 'presence deleted';
  assert not exists (select 1 from public.places where user_id = me), 'places deleted';
  assert not exists (select 1 from public.matches where me in (user_a, user_b)), 'matches deleted';
end $$;

\echo 'All backend tests passed.'
