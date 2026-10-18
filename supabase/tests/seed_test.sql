-- A newcomer with the simulator test persona's places should see the demo people.
\set ON_ERROR_STOP on
set client_min_messages = warning;

insert into auth.users (id) values ('00000000-0000-0000-0000-0000000000aa');
insert into public.profiles (id, first_name, birthday, gender, show_me, intent)
values ('00000000-0000-0000-0000-0000000000aa', 'Alex', '1998-10-18', 'woman', 'everyone', 'dating');

-- Build the payload as the database owner (the helpers aren't callable by app users).
create temp table payload as select
  jsonb_build_array(
    jsonb_build_object('place_key', tp_private.geohash_encode(51.5450, -0.0553), 'cells', jsonb_build_array(tp_private.geohash_encode(51.5450, -0.0553)),
                       'category', 'Café', 'neighbourhood', 'Hackney', 'venue_name', 'My café', 'visit_days', 60),
    jsonb_build_object('place_key', tp_private.geohash_encode(51.5270, -0.0550), 'cells', jsonb_build_array(tp_private.geohash_encode(51.5270, -0.0550)),
                       'category', 'Climbing gym', 'neighbourhood', 'Bethnal Green', 'venue_name', 'My gym', 'visit_days', 25)) as places,
  jsonb_build_array(
    jsonb_build_object('moment_key', 'glasto', 'area5', left(tp_private.geohash_encode(51.1550, -2.5850), 5), 'title', 'Pilton',
                       'starts_on', tp_private.last_occurrence(6, 26), 'ends_on', tp_private.last_occurrence(6, 28))) as moments,
  (select jsonb_agg(jsonb_build_object('area', tp_private.geohash_encode(51.5450, -0.0553),
                                       'hour', date_trunc('week', now()) - make_interval(weeks => w) + interval '1 day 7 hours'))
   from generate_series(1, 40) w)
  || jsonb_build_array(jsonb_build_object('area', tp_private.geohash_encode(51.1550, -2.5850),
                                          'hour', tp_private.last_occurrence(6, 27)::timestamp at time zone 'utc' + interval '20 hours')) as presence;
grant select on payload to authenticated;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000aa', false);
set role authenticated;

select public.sync_my_places(places, moments, presence) from payload;

create temp table feed as select * from public.get_feed(20) with ordinality;

do $$
declare
  r record;
  result jsonb;
  matches int := 0;
begin
  for r in select ordinality, first_name, round(score::numeric, 3) s, crossings->0->>'tier' t from feed order by ordinality loop
    raise warning 'seed feed %: % (%, %)', r.ordinality, r.first_name, r.s, r.t;
  end loop;
  assert (select first_name from feed where ordinality = 1) = 'Maya', 'Maya, the café regular, leads';
  assert (select count(*) from feed) >= 4, 'several demo people show up';
  assert exists (select 1 from feed where first_name = 'Maya' and crossings @> '[{"kind": "moment"}]'),
    'Maya was at the same festival';

  for r in select person_id from feed loop
    result := public.like_person(r.person_id, 'first');
    if (result->>'matched')::boolean then matches := matches + 1; end if;
  end loop;
  raise warning 'matches from liking everyone: %', matches;
  assert matches >= 1, 'demo people like back';
  assert (select count(*) from public.get_matches()) = matches, 'matches are listed';
end $$;
reset role;

\echo 'Seed tests passed.'
