-- Demo people for development. They live around the same London places as the simulator's
-- test photos (Tools/seed-photos.swift), so a fresh install has real accounts to cross paths with.
-- Demo profiles like you back about half the time, so matches can be tested.
-- Do not run this on a production project.

create or replace function tp_private.cells_around(lat double precision, lon double precision)
returns text[]
language sql
immutable
as $$
  select array_agg(distinct tp_private.geohash_encode(lat + dy, lon + dx))
  from unnest(array[-0.0012, 0, 0.0012]) dy, unnest(array[-0.0012, 0, 0.0012]) dx;
$$;

-- The most recent past occurrence of a month/day.
create or replace function tp_private.last_occurrence(m int, d int)
returns date
language sql
stable
as $$
  select case when make_date(extract(year from now())::int, m, d) <= current_date
              then make_date(extract(year from now())::int, m, d)
              else make_date(extract(year from now())::int - 1, m, d) end;
$$;

create temp table demo_people (key text, id uuid, first_name text, birthday date, gender text, show_me text,
                               intent text, question text, answer text);
insert into demo_people values
  ('maya',  'd0000000-0000-4000-8000-000000000001', 'Maya',  '1997-03-12', 'woman',     'everyone', 'both',
   'My third place is…', 'The lido at 8 am, before anyone else is up.'),
  ('jonah', 'd0000000-0000-4000-8000-000000000002', 'Jonah', '1995-07-02', 'man',       'everyone', 'both',
   'Best place I’ve been to twice', 'A tiny bookshop that still writes receipts by hand.'),
  ('leila', 'd0000000-0000-4000-8000-000000000003', 'Leila', '1999-01-20', 'woman',     'everyone', 'both',
   'A perfect Sunday', 'Long swim, longer breakfast, a film I’ve already seen.'),
  ('sam',   'd0000000-0000-4000-8000-000000000004', 'Sam',   '1996-10-08', 'man',       'everyone', 'both',
   'Unpopular opinion', 'Bad weather is the best weather for a walk.'),
  ('ana',   'd0000000-0000-4000-8000-000000000005', 'Ana',   '1998-05-27', 'woman',     'everyone', 'both',
   'You’ll find me', 'Front left at every gig, whether I like the band or not.'),
  ('theo',  'd0000000-0000-4000-8000-000000000006', 'Theo',  '1994-12-14', 'man',       'everyone', 'both',
   'Green flag', 'You know the barista’s name.'),
  ('noor',  'd0000000-0000-4000-8000-000000000007', 'Noor',  '2000-08-30', 'nonbinary', 'everyone', 'both',
   'I’ll know it’s going well if…', 'We find a café neither of us has been to yet.');

insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
select id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
       'demo-' || key || '@thirdplace.invalid', now(), now(), '{"provider": "email", "providers": ["email"]}', '{}'
from demo_people
on conflict (id) do nothing;

insert into public.profiles (id, first_name, birthday, gender, show_me, intent, prompt_question, prompt_answer, verified, is_demo)
select id, first_name, birthday, gender, show_me, intent, question, answer, true, true
from demo_people
on conflict (id) do nothing;

-- Places: who goes where, and when (weekday 0 = Monday, hour in UTC, share of weeks).
create temp table demo_places (who text, spot text, lat double precision, lon double precision, category text,
                               hood text, venue text, rhythm text, weekday int, hour int, share double precision);
insert into demo_places values
  ('maya',  'cafe',     51.5450, -0.0553, 'Café',         'Hackney',         'Neighbourhood café',  'Tue and Thu mornings', 1, 7, 0.8),
  ('maya',  'cafe',     51.5450, -0.0553, 'Café',         'Hackney',         'Neighbourhood café',  'Tue and Thu mornings', 3, 7, 0.7),
  ('jonah', 'climbing', 51.5270, -0.0550, 'Climbing gym', 'Bethnal Green',   'Climbing wall',       'Thursday evenings',    3, 17, 0.4),
  ('jonah', 'bookshop', 51.5620, -0.0750, 'Bookshop',     'Stoke Newington', 'Corner bookshop',     'Saturday afternoons',  5, 13, 0.3),
  ('leila', 'lido',     51.5420, -0.0610, 'Pool',         'Hackney',         'Outdoor lido',        'Summer weekends',      5, 9, 0.3),
  ('leila', 'park',     51.5362, -0.0402, 'Park',         'Tower Hamlets',   'Victoria Park',       'Sunday mornings',      6, 8, 0.3),
  ('sam',   'park',     51.5362, -0.0402, 'Park',         'Tower Hamlets',   'Victoria Park',       'Sunday mornings',      6, 8, 0.7),
  ('ana',   'bookshop', 51.5620, -0.0750, 'Bookshop',     'Stoke Newington', 'Corner bookshop',     'Saturday afternoons',  5, 13, 0.6),
  ('theo',  'pub',      51.5297, -0.0712, 'Bar',          'Columbia Road',   'Corner pub',          'Friday nights',        4, 19, 0.5),
  ('theo',  'cafe',     51.5450, -0.0553, 'Café',         'Hackney',         'Neighbourhood café',  'Weekday mornings',     1, 8, 0.3),
  ('noor',  'climbing', 51.5270, -0.0550, 'Climbing gym', 'Bethnal Green',   'Climbing wall',       'Tue and Thu evenings', 1, 17, 0.6),
  ('noor',  'climbing', 51.5270, -0.0550, 'Climbing gym', 'Bethnal Green',   'Climbing wall',       'Tue and Thu evenings', 3, 17, 0.6);

insert into public.places (user_id, place_key, cells, category, neighbourhood, venue_name, rhythm, visit_days)
select distinct on (p.id, dp.spot)
       p.id, tp_private.geohash_encode(dp.lat, dp.lon), tp_private.cells_around(dp.lat, dp.lon),
       dp.category, dp.hood, dp.venue, dp.rhythm,
       round(52 * dp.share)::int
from demo_places dp join demo_people p on p.key = dp.who
on conflict do nothing;

select setseed(0.42);
insert into public.presence (user_id, area, hour)
select p.id, tp_private.geohash_encode(dp.lat, dp.lon),
       date_trunc('week', now()) - make_interval(weeks => w) + make_interval(days => dp.weekday, hours => dp.hour)
from demo_places dp
join demo_people p on p.key = dp.who
cross join generate_series(1, 52) w
where random() < dp.share
  and (dp.spot <> 'lido' or extract(month from date_trunc('week', now()) - make_interval(weeks => w)) between 6 and 8)
on conflict do nothing;

-- Moments: the festival and trips from the test photos, every hour of the evening.
create temp table demo_moments (who text, lat double precision, lon double precision, title text, m int, d int, days int, from_hour int, to_hour int);
insert into demo_moments values
  ('maya', 51.1550, -2.5850, 'Pilton',    6, 26, 3, 9, 22),
  ('leila', 41.4110, 2.2210, 'Barcelona', 5, 30, 2, 14, 22),
  ('ana',  38.7075, -9.1365, 'Lisbon',   12, 31, 1, 17, 23),
  ('noor', 41.0200, 28.9730, 'Istanbul',  8, 14, 1, 12, 21);

insert into public.moments (user_id, moment_key, area5, title, starts_on, ends_on)
select p.id, left(tp_private.geohash_encode(dm.lat, dm.lon), 5) || '-' || dm.m || '-' || dm.d,
       left(tp_private.geohash_encode(dm.lat, dm.lon), 5), dm.title,
       tp_private.last_occurrence(dm.m, dm.d), tp_private.last_occurrence(dm.m, dm.d) + dm.days - 1
from demo_moments dm join demo_people p on p.key = dm.who
on conflict do nothing;

insert into public.presence (user_id, area, hour)
select p.id, tp_private.geohash_encode(dm.lat, dm.lon),
       (tp_private.last_occurrence(dm.m, dm.d) + day)::timestamp at time zone 'utc' + make_interval(hours => h)
from demo_moments dm
join demo_people p on p.key = dm.who
cross join generate_series(0, 2) day
cross join generate_series(0, 23) h
where day < dm.days and h between dm.from_hour and dm.to_hour
on conflict do nothing;

-- Demo people like you back about half the time.
create or replace function tp_private.demo_like_back()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (select 1 from public.profiles where id = new.to_user and is_demo)
     and abs(hashtext(new.from_user::text || new.to_user::text)) % 2 = 0 then
    insert into public.likes (from_user, to_user, item) values (new.to_user, new.from_user, 'first')
    on conflict do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists demo_like_back on public.likes;
create trigger demo_like_back
after insert on public.likes
for each row execute function tp_private.demo_like_back();

-- Demo people reply to chat messages, so conversations can be tested end to end.
create or replace function tp_private.demo_reply()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  other uuid := case when new.sender = new.user_a then new.user_b else new.user_a end;
  replies text[] := array[
    'Ha, small world. Do you usually sit by the window?',
    'I think I''ve seen you there! Were you the one with the green notebook?',
    'Okay this is a bit wild. Coffee there on Thursday?',
    'Same time next week then?'
  ];
  n int;
begin
  if not exists (select 1 from public.profiles where id = other and is_demo) then
    return new;
  end if;
  select count(*) into n from public.messages where user_a = new.user_a and user_b = new.user_b and sender = other;
  if n < array_length(replies, 1) then
    insert into public.messages (user_a, user_b, sender, body)
    values (new.user_a, new.user_b, other, replies[n + 1]);
  end if;
  return new;
end;
$$;

drop trigger if exists demo_reply on public.messages;
create trigger demo_reply
after insert on public.messages
for each row execute function tp_private.demo_reply();
