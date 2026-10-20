-- Profiles get up to three prompts instead of one, every photo and prompt can be liked, and
-- photo paths must point into the person's own folder.

create or replace function tp_private.valid_prompts(p jsonb)
returns boolean
language plpgsql
immutable
as $$
declare
  e jsonb;
  seen text[] := '{}';
begin
  if jsonb_typeof(p) <> 'array' or jsonb_array_length(p) > 3 then return false; end if;
  for e in select value from jsonb_array_elements(p) loop
    if jsonb_typeof(e) <> 'object' then return false; end if;
    if coalesce(jsonb_typeof(e -> 'q'), '') <> 'string' or coalesce(jsonb_typeof(e -> 'a'), '') <> 'string' then
      return false;
    end if;
    if (select count(*) from jsonb_object_keys(e)) <> 2 then return false; end if;
    if char_length(e ->> 'q') not between 1 and 80 or char_length(btrim(e ->> 'a')) not between 1 and 200 then
      return false;
    end if;
    if (e ->> 'q') = any (seen) then return false; end if;
    seen := seen || (e ->> 'q');
  end loop;
  return true;
end;
$$;

create or replace function tp_private.own_photo_paths(owner uuid, paths text[])
returns boolean
language sql
immutable
as $$
  select coalesce(bool_and(p like owner::text || '/%' and position('..' in p) = 0), true)
  from unnest(paths) as p;
$$;

alter table public.profiles
  add column prompts jsonb not null default '[]'
  constraint profiles_prompts_valid check (tp_private.valid_prompts(prompts));

update public.profiles
set prompts = jsonb_build_array(jsonb_build_object('q', prompt_question, 'a', btrim(prompt_answer)))
where prompt_question is not null and char_length(prompt_question) > 0
  and prompt_answer is not null and btrim(prompt_answer) <> '';

alter table public.profiles
  add constraint profiles_own_photo_paths check (tp_private.own_photo_paths(id, photo_paths));

-- get_feed returns the prompts array instead of the single question and answer.
drop function public.get_feed(int);

alter table public.profiles drop column prompt_question, drop column prompt_answer;

-- photo1..photo6 and prompt1..prompt3; 'prompt' stays valid for likes made before this change.
alter table public.likes drop constraint likes_item_check;
alter table public.likes add constraint likes_item_check check (item in (
  'photo1', 'photo2', 'photo3', 'photo4', 'photo5', 'photo6',
  'prompt1', 'prompt2', 'prompt3', 'prompt', 'first', 'second'
));

create or replace function public.get_feed(max_results int default 20)
returns table (
  person_id uuid,
  first_name text,
  age int,
  verified boolean,
  photo_paths text[],
  prompts jsonb,
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
         e.prompts,
         s.hood,
         least(1.0, 0.75 * coalesce(s.sim, 0) + 0.10 * (1 - exp(-s.hours / 4.0)) + case when s.same_top then 0.15 else 0 end)::float8,
         tp_private.crossings(me, e.id)
  from scored s
  join eligible e on e.id = s.id
  order by 8 desc, e.id
  limit max_results;
end;
$$;

revoke execute on function public.get_feed(int) from public, anon;
grant execute on function public.get_feed(int) to authenticated;
