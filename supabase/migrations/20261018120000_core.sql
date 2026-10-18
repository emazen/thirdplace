-- Third Place core schema.
--
-- Privacy model:
--   * Photos never reach the server. Only blurred presence does: a ~150 m area (geohash 7) and an hour.
--   * Presence is accepted only inside places and moments the user chose to keep, so home and work
--     can't be uploaded even by mistake (enforced by a trigger, not just the app).
--   * Nobody can read another person's places or presence directly. The feed and matches are served
--     by security-definer functions that return only what the product shows: a category and a
--     neighbourhood before a match, the venue after one.

create schema if not exists tp_private;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create or replace function tp_private.geohash_encode(lat double precision, lon double precision, len int default 7)
returns text
language plpgsql
immutable
as $$
declare
  alphabet constant text := '0123456789bcdefghjkmnpqrstuvwxyz';
  lat_lo double precision := -90;  lat_hi double precision := 90;
  lon_lo double precision := -180; lon_hi double precision := 180;
  hash text := '';
  b int := 0;
  ch int := 0;
  even boolean := true;
  mid double precision;
begin
  while length(hash) < len loop
    if even then
      mid := (lon_lo + lon_hi) / 2;
      if lon >= mid then ch := ch | (1 << (4 - b)); lon_lo := mid; else lon_hi := mid; end if;
    else
      mid := (lat_lo + lat_hi) / 2;
      if lat >= mid then ch := ch | (1 << (4 - b)); lat_lo := mid; else lat_hi := mid; end if;
    end if;
    even := not even;
    if b < 4 then
      b := b + 1;
    else
      hash := hash || substr(alphabet, ch + 1, 1);
      b := 0;
      ch := 0;
    end if;
  end loop;
  return hash;
end;
$$;

-- Does someone who wants `show_me` want to see a person of `gender`?
create or replace function tp_private.wants(show_me text, gender text)
returns boolean
language sql
immutable
as $$
  select case show_me
    when 'everyone' then true
    when 'women' then gender = 'woman'
    when 'men' then gender = 'man'
    else false
  end;
$$;

create or replace function tp_private.intent_ok(a text, b text)
returns boolean
language sql
immutable
as $$
  select a = 'both' or b = 'both' or a = b;
$$;

-- Week index in the last 52 weeks (0 = oldest, 51 = this week), or null if older.
create or replace function tp_private.week_index(ts timestamptz)
returns int
language sql
stable
as $$
  select case when back between 0 and 51 then 51 - back end
  from (select floor(extract(epoch from date_trunc('week', now()) - date_trunc('week', ts)) / 604800)::int as back) w;
$$;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  first_name text not null check (char_length(first_name) between 1 and 40),
  birthday date not null check (birthday <= current_date - interval '18 years'),
  gender text not null check (gender in ('woman', 'man', 'nonbinary')),
  show_me text not null check (show_me in ('women', 'men', 'everyone')),
  intent text not null check (intent in ('dating', 'friends', 'both')),
  prompt_question text check (char_length(prompt_question) <= 80),
  prompt_answer text check (char_length(prompt_answer) <= 200),
  photo_paths text[] not null default '{}' check (cardinality(photo_paths) <= 6),
  verified boolean not null default false,
  is_demo boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- A third place the user kept. place_key is the cluster's peak cell; cells is the whole cluster.
create table public.places (
  user_id uuid not null references public.profiles (id) on delete cascade,
  place_key text not null check (place_key ~ '^[0-9b-hjkmnp-z]{7}$'),
  cells text[] not null check (cardinality(cells) between 1 and 64),
  category text not null check (char_length(category) <= 40),
  neighbourhood text not null check (char_length(neighbourhood) <= 80),
  venue_name text check (char_length(venue_name) <= 120),
  rhythm text check (char_length(rhythm) <= 60),
  visit_days int not null default 0 check (visit_days >= 0),
  primary key (user_id, place_key)
);
create index places_cells on public.places using gin (cells);

-- A one-off occasion the user kept (festival, trip). area5 is a ~5 km cell.
create table public.moments (
  user_id uuid not null references public.profiles (id) on delete cascade,
  moment_key text not null check (char_length(moment_key) <= 40),
  area5 text not null check (area5 ~ '^[0-9b-hjkmnp-z]{5}$'),
  title text not null check (char_length(title) <= 80),
  starts_on date not null,
  ends_on date not null check (ends_on >= starts_on),
  primary key (user_id, moment_key)
);

-- Blurred presence: the only location data the server ever holds.
create table public.presence (
  user_id uuid not null references public.profiles (id) on delete cascade,
  area text not null check (area ~ '^[0-9b-hjkmnp-z]{7}$'),
  hour timestamptz not null check (date_trunc('hour', hour) = hour),
  primary key (user_id, area, hour)
);
create index presence_area_hour on public.presence (area, hour);
create index presence_area6_hour on public.presence (left(area, 6), hour);

create table public.likes (
  from_user uuid not null references public.profiles (id) on delete cascade,
  to_user uuid not null references public.profiles (id) on delete cascade,
  item text not null check (item in ('photo1', 'photo2', 'first', 'second', 'prompt')),
  comment text check (char_length(comment) <= 300),
  created_at timestamptz not null default now(),
  primary key (from_user, to_user),
  check (from_user <> to_user)
);
create index likes_to_user on public.likes (to_user);

create table public.passes (
  from_user uuid not null references public.profiles (id) on delete cascade,
  to_user uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (from_user, to_user)
);

create table public.blocks (
  blocker uuid not null references public.profiles (id) on delete cascade,
  blocked uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker, blocked)
);

create table public.matches (
  user_a uuid not null references public.profiles (id) on delete cascade,
  user_b uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_a, user_b),
  check (user_a < user_b)
);

-- ---------------------------------------------------------------------------
-- Guards
-- ---------------------------------------------------------------------------

create or replace function tp_private.presence_guard()
returns trigger
language plpgsql
security definer
set search_path = public, tp_private
as $$
begin
  if new.hour > now() + interval '1 hour' then
    raise exception 'presence in the future is not accepted';
  end if;
  if not exists (
       select 1 from places p where p.user_id = new.user_id and new.area = any (p.cells))
     and not exists (
       select 1 from moments m
       where m.user_id = new.user_id
         and left(new.area, 5) = m.area5
         and (new.hour at time zone 'utc')::date between m.starts_on - 1 and m.ends_on + 1)
  then
    raise exception 'presence outside kept places and moments is not accepted';
  end if;
  return new;
end;
$$;

create trigger presence_guard
before insert or update on public.presence
for each row execute function tp_private.presence_guard();

create or replace function tp_private.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger profiles_touch
before update on public.profiles
for each row execute function tp_private.touch_updated_at();

-- Users can't promote themselves to verified or demo; only the server sets those.
create or replace function tp_private.protect_profile_flags()
returns trigger
language plpgsql
as $$
begin
  if current_user in ('authenticated', 'anon') then
    if tg_op = 'INSERT' then
      new.verified := false;
      new.is_demo := false;
    else
      new.verified := old.verified;
      new.is_demo := old.is_demo;
    end if;
  end if;
  return new;
end;
$$;

create trigger profiles_protect_flags
before insert or update on public.profiles
for each row execute function tp_private.protect_profile_flags();

-- ---------------------------------------------------------------------------
-- Row level security: own rows only. Everything about other people goes through functions.
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.places enable row level security;
alter table public.moments enable row level security;
alter table public.presence enable row level security;
alter table public.likes enable row level security;
alter table public.passes enable row level security;
alter table public.blocks enable row level security;
alter table public.matches enable row level security;

create policy "own profile" on public.profiles
  for all to authenticated using (id = auth.uid()) with check (id = auth.uid());

create policy "own places" on public.places
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "own moments" on public.moments
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "own presence" on public.presence
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Likes are sent through like_person() so the daily limit can't be bypassed.
create policy "see likes I sent" on public.likes
  for select to authenticated using (from_user = auth.uid());

create policy "own passes" on public.passes
  for all to authenticated using (from_user = auth.uid()) with check (from_user = auth.uid());

create policy "own blocks" on public.blocks
  for all to authenticated using (blocker = auth.uid()) with check (blocker = auth.uid());

create policy "my matches" on public.matches
  for select to authenticated using (auth.uid() in (user_a, user_b));

revoke all on schema tp_private from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Writing your places
-- ---------------------------------------------------------------------------

-- Replaces the caller's places, moments and presence in one transaction.
-- places:   [{place_key, cells[], category, neighbourhood, venue_name, rhythm, visit_days}]
-- moments:  [{moment_key, area5, title, starts_on, ends_on}]
-- presence: [{area, hour}]
create or replace function public.sync_my_places(kept_places jsonb, kept_moments jsonb, blurred_presence jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, tp_private
as $$
declare
  me uuid := auth.uid();
  kept int;
begin
  if me is null then raise exception 'not signed in'; end if;
  if not exists (select 1 from public.profiles where id = me) then raise exception 'create a profile first'; end if;
  if jsonb_array_length(blurred_presence) > 20000 then raise exception 'too much presence in one sync'; end if;

  delete from public.presence where user_id = me;
  delete from public.places where user_id = me;
  delete from public.moments where user_id = me;

  insert into public.places (user_id, place_key, cells, category, neighbourhood, venue_name, rhythm, visit_days)
  select me, p.place_key, p.cells, p.category, p.neighbourhood, p.venue_name, p.rhythm, coalesce(p.visit_days, 0)
  from jsonb_to_recordset(kept_places) as p(place_key text, cells text[], category text, neighbourhood text,
                                       venue_name text, rhythm text, visit_days int);

  insert into public.moments (user_id, moment_key, area5, title, starts_on, ends_on)
  select me, m.moment_key, m.area5, m.title, m.starts_on, m.ends_on
  from jsonb_to_recordset(kept_moments) as m(moment_key text, area5 text, title text, starts_on date, ends_on date);

  -- Rows outside kept places/moments are skipped here rather than failing the whole sync;
  -- the trigger still rejects any direct insert.
  insert into public.presence (user_id, area, hour)
  select distinct me, x.area, date_trunc('hour', x.hour)
  from jsonb_to_recordset(blurred_presence) as x(area text, hour timestamptz)
  where exists (select 1 from public.places p where p.user_id = me and x.area = any (p.cells))
     or exists (select 1 from public.moments m
                where m.user_id = me and left(x.area, 5) = m.area5
                  and (x.hour at time zone 'utc')::date between m.starts_on - 1 and m.ends_on + 1)
  on conflict do nothing;

  get diagnostics kept = row_count;
  return jsonb_build_object('places', jsonb_array_length(kept_places), 'moments', jsonb_array_length(kept_moments), 'presence', kept);
end;
$$;

-- ---------------------------------------------------------------------------
-- Before sign-up: how many people share these places? Counts only, never fewer than 2.
-- input: [{key, cells[]}]  output: {places: {key: people}, total: distinct people}
-- ---------------------------------------------------------------------------

create or replace function public.preview_overlaps(candidate_places jsonb)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with input as (
    select x.key, x.cells from jsonb_to_recordset(candidate_places) as x(key text, cells text[])
  ),
  hits as (
    select i.key, p.user_id
    from input i
    join public.places p on p.cells && i.cells and p.user_id is distinct from auth.uid()
  ),
  per_place as (
    select i.key, count(distinct h.user_id) as n
    from input i left join hits h on h.key = i.key
    group by i.key
  )
  select jsonb_build_object(
    'places', coalesce((select jsonb_object_agg(key, case when n >= 2 then n else 0 end) from per_place), '{}'::jsonb),
    'total', (select case when count(distinct user_id) >= 2 then count(distinct user_id) else 0 end from hits)
  );
$$;

-- ---------------------------------------------------------------------------
-- Crossings: what two people have in common, as the feed shows it.
-- ---------------------------------------------------------------------------

create or replace function tp_private.crossings(a uuid, b uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, tp_private
as $$
declare
  pair record;
  a_weeks int[];
  b_weeks int[];
  common int;
  same_hour boolean;
  near_miss boolean;
  same_day boolean;
  tier text;
  result jsonb := '[]'::jsonb;
  moment record;
begin
  -- Strongest shared place: the pair with the most combined visit days.
  select pa.place_key as a_key, pa.cells as a_cells, pa.category, pa.neighbourhood, pa.rhythm,
         pb.cells as b_cells
  into pair
  from places pa
  join places pb on pb.user_id = b and pb.cells && pa.cells
  where pa.user_id = a
  order by pa.visit_days + pb.visit_days desc, pa.place_key
  limit 1;

  if found then
    select coalesce(array_agg(distinct tp_private.week_index(hour)) filter (where tp_private.week_index(hour) is not null), '{}')
      into a_weeks from presence where user_id = a and area = any (pair.a_cells);
    select coalesce(array_agg(distinct tp_private.week_index(hour)) filter (where tp_private.week_index(hour) is not null), '{}')
      into b_weeks from presence where user_id = b and area = any (pair.b_cells);
    select count(*) into common from (select unnest(a_weeks) intersect select unnest(b_weeks)) w;

    select exists (
      select 1 from presence x join presence y on y.area = x.area and y.hour = x.hour
      where x.user_id = a and y.user_id = b and x.area = any (pair.a_cells || pair.b_cells)
    ) into same_hour;
    select exists (
      select 1 from presence x join presence y on y.area = x.area and abs(extract(epoch from y.hour - x.hour)) = 3600
      where x.user_id = a and y.user_id = b and x.area = any (pair.a_cells || pair.b_cells)
    ) into near_miss;
    select exists (
      select 1 from presence x join presence y
        on y.area = x.area and (y.hour at time zone 'utc')::date = (x.hour at time zone 'utc')::date
      where x.user_id = a and y.user_id = b and x.area = any (pair.a_cells || pair.b_cells)
    ) into same_day;

    tier := case
      when common >= 3 then 'regulars'
      when near_miss then 'near_miss'
      when same_hour then 'same_moment'
      when same_day then 'same_day'
      else 'same_place'
    end;

    result := result || jsonb_build_array(jsonb_build_object(
      'kind', 'place',
      'tier', tier,
      'category', pair.category,
      'neighbourhood', pair.neighbourhood,
      'rhythm', pair.rhythm,
      'my_weeks', to_jsonb(a_weeks),
      'their_weeks', to_jsonb(b_weeks),
      'weeks_in_common', common
    ));
  end if;

  -- Same hour within ~1.2 km somewhere that isn't one of a's places: a gig, a festival, a trip.
  select x.hour, mo.title
  into moment
  from presence x
  join presence y on left(y.area, 6) = left(x.area, 6) and y.hour = x.hour and y.user_id = b
  left join moments mo on mo.user_id = a and mo.area5 = left(x.area, 5)
                      and (x.hour at time zone 'utc')::date between mo.starts_on - 1 and mo.ends_on + 1
  where x.user_id = a
    and not exists (select 1 from places p where p.user_id = a and x.area = any (p.cells))
  order by x.hour desc
  limit 1;

  if found then
    result := result || jsonb_build_array(jsonb_build_object(
      'kind', 'moment',
      'tier', 'same_moment',
      'title', coalesce(moment.title, 'a big night out'),
      'date', (moment.hour at time zone 'utc')::date
    ));
  end if;

  return result;
end;
$$;

-- ---------------------------------------------------------------------------
-- The feed: everyone you crossed paths with, best first.
--
-- score = 0.75 · similarity + 0.10 · co-presence + 0.15 if you share a #1 place
--   similarity:   cosine of place profiles (share of visit days per place), each place weighted by
--                 specificity ln((N+1)/(n+1))+1 so a tiny bookshop beats a huge park
--   co-presence:  1 − e^(−shared hours / 4)
-- Mirrors ThirdPlaceCore/Affinity.swift.
-- ---------------------------------------------------------------------------

create or replace function public.get_feed(max_results int default 20)
returns table (
  person_id uuid,
  first_name text,
  age int,
  verified boolean,
  photo_paths text[],
  prompt_question text,
  prompt_answer text,
  neighbourhood text,
  score double precision,
  crossings jsonb
)
language plpgsql
stable
security definer
set search_path = public, tp_private
as $$
#variable_conflict use_column
declare
  me uuid := auth.uid();
  my public.profiles%rowtype;
  total_users int;
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into my from public.profiles where id = me;
  if not found then return; end if;
  select count(*) into total_users from public.profiles;

  return query
  with cell_users as (
    select c.cell, count(distinct p.user_id)::int as n
    from public.places p, unnest(p.cells) as c(cell)
    group by c.cell
  ),
  place_vec as (
    select p.user_id, p.place_key, p.cells, p.neighbourhood,
           greatest(p.visit_days, 1)::float8 / sum(greatest(p.visit_days, 1)) over (partition by p.user_id) as w,
           ln((total_users + 1)::float8 /
              (coalesce((select max(cu.n) from cell_users cu where cu.cell = any (p.cells)), 0) + 1)) + 1 as spec
    from public.places p
  ),
  norms as (
    select user_id, sqrt(sum((w * spec) ^ 2)) as norm from place_vec group by user_id
  ),
  tops as (
    select distinct on (user_id) user_id, cells from place_vec order by user_id, w desc, place_key
  ),
  pairs as (
    select o.user_id as other, (m.w * m.spec) * (o.w * o.spec) as contrib, o.neighbourhood
    from place_vec m
    join place_vec o on o.user_id <> m.user_id and o.cells && m.cells
    where m.user_id = me
  ),
  shared_hours as (
    select y.user_id as other, count(*)::int as hours
    from public.presence x
    join public.presence y on y.area = x.area and y.hour = x.hour and y.user_id <> x.user_id
    where x.user_id = me
    group by y.user_id
  ),
  moment_people as (
    select distinct y.user_id as other
    from public.presence x
    join public.presence y on left(y.area, 6) = left(x.area, 6) and y.hour = x.hour and y.user_id <> x.user_id
    where x.user_id = me
      and not exists (select 1 from public.places p where p.user_id = me and x.area = any (p.cells))
  ),
  candidates as (
    select other from pairs union select other from moment_people
  ),
  eligible as (
    select pr.*
    from candidates c
    join public.profiles pr on pr.id = c.other
    where tp_private.wants(my.show_me, pr.gender)
      and tp_private.wants(pr.show_me, my.gender)
      and tp_private.intent_ok(my.intent, pr.intent)
      and not exists (select 1 from public.blocks bl
                      where (bl.blocker = me and bl.blocked = pr.id) or (bl.blocker = pr.id and bl.blocked = me))
      and not exists (select 1 from public.likes l where l.from_user = me and l.to_user = pr.id)
      and not exists (select 1 from public.passes ps where ps.from_user = me and ps.to_user = pr.id)
      and not exists (select 1 from public.matches mt where mt.user_a = least(me, pr.id) and mt.user_b = greatest(me, pr.id))
  ),
  scored as (
    select e.id,
           coalesce((select sum(contrib) from pairs where other = e.id), 0)
             / nullif((select norm from norms where user_id = me) * (select norm from norms where user_id = e.id), 0) as sim,
           coalesce((select hours from shared_hours where other = e.id), 0) as hours,
           exists (select 1 from tops t1, tops t2
                   where t1.user_id = me and t2.user_id = e.id and t1.cells && t2.cells) as same_top,
           (select neighbourhood from pairs where other = e.id order by contrib desc limit 1) as hood
    from eligible e
  )
  select e.id,
         e.first_name,
         extract(year from age(e.birthday))::int,
         e.verified,
         e.photo_paths,
         e.prompt_question,
         e.prompt_answer,
         s.hood,
         least(1.0, 0.75 * coalesce(s.sim, 0) + 0.10 * (1 - exp(-s.hours / 4.0)) + case when s.same_top then 0.15 else 0 end)::float8,
         tp_private.crossings(me, e.id)
  from scored s
  join eligible e on e.id = s.id
  order by 9 desc, e.id
  limit max_results;
end;
$$;

-- ---------------------------------------------------------------------------
-- Likes, passes, matches
-- ---------------------------------------------------------------------------

create or replace function public.likes_left()
returns int
language sql
stable
security definer
set search_path = public
as $$
  select greatest(0, 8 - count(*)::int)
  from public.likes
  where from_user = auth.uid() and created_at >= date_trunc('day', now());
$$;

create or replace function public.like_person(target uuid, item text, comment text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  remaining int;
  matched boolean := false;
begin
  if me is null then raise exception 'not signed in'; end if;
  if target = me then raise exception 'you can''t like yourself'; end if;
  if exists (select 1 from public.blocks
             where (blocker = me and blocked = target) or (blocker = target and blocked = me)) then
    raise exception 'this person isn''t available';
  end if;

  remaining := public.likes_left();
  if remaining <= 0 then
    return jsonb_build_object('ok', false, 'reason', 'out_of_likes', 'likes_left', 0, 'matched', false);
  end if;

  insert into public.likes (from_user, to_user, item, comment)
  values (me, target, item, comment)
  on conflict do nothing;

  if exists (select 1 from public.likes where from_user = target and to_user = me) then
    insert into public.matches (user_a, user_b) values (least(me, target), greatest(me, target))
    on conflict do nothing;
    matched := true;
  end if;

  return jsonb_build_object('ok', true, 'matched', matched, 'likes_left', public.likes_left());
end;
$$;

create or replace function public.pass_person(target uuid)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.passes (from_user, to_user) values (auth.uid(), target) on conflict do nothing;
$$;

-- Matches, with the exact shared venues now revealed to both people.
create or replace function public.get_matches()
returns table (
  person_id uuid,
  first_name text,
  age int,
  photo_paths text[],
  matched_at timestamptz,
  shared_places jsonb
)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  return query
  select pr.id,
         pr.first_name,
         extract(year from age(pr.birthday))::int,
         pr.photo_paths,
         mt.created_at,
         coalesce((
           select jsonb_agg(distinct jsonb_build_object(
                    'category', mine.category,
                    'neighbourhood', mine.neighbourhood,
                    'my_venue', mine.venue_name,
                    'their_venue', theirs.venue_name))
           from public.places mine
           join public.places theirs on theirs.user_id = pr.id and theirs.cells && mine.cells
           where mine.user_id = me
         ), '[]'::jsonb)
  from public.matches mt
  join public.profiles pr on pr.id = case when mt.user_a = me then mt.user_b else mt.user_a end
  where me in (mt.user_a, mt.user_b)
  order by mt.created_at desc;
end;
$$;

-- "Delete your account in two taps. Everything is gone the same day."
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  delete from auth.users where id = auth.uid();
end;
$$;

-- ---------------------------------------------------------------------------
-- Function access
-- ---------------------------------------------------------------------------

revoke execute on all functions in schema public from public, anon;
grant execute on function public.preview_overlaps(jsonb) to anon, authenticated;
grant execute on function public.sync_my_places(jsonb, jsonb, jsonb) to authenticated;
grant execute on function public.get_feed(int) to authenticated;
grant execute on function public.likes_left() to authenticated;
grant execute on function public.like_person(uuid, text, text) to authenticated;
grant execute on function public.pass_person(uuid) to authenticated;
grant execute on function public.get_matches() to authenticated;
grant execute on function public.delete_my_account() to authenticated;
