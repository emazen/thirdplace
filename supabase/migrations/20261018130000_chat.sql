-- Chat between matches, plus the safety exits every dating app needs: unmatch, block, report.
--
-- Only matched people can message each other. Unmatching or blocking deletes the conversation
-- for both sides, and blocked people never appear in each other's feed again.

create table public.messages (
  id bigint generated always as identity primary key,
  user_a uuid not null,
  user_b uuid not null,
  sender uuid not null references public.profiles (id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 1000),
  created_at timestamptz not null default now(),
  read_at timestamptz,
  foreign key (user_a, user_b) references public.matches (user_a, user_b) on delete cascade,
  check (sender in (user_a, user_b))
);
create index messages_conversation on public.messages (user_a, user_b, id);

create table public.reports (
  id bigint generated always as identity primary key,
  reporter uuid not null references public.profiles (id) on delete cascade,
  reported uuid not null references public.profiles (id) on delete cascade,
  reason text not null check (reason in ('fake', 'inappropriate', 'harassment', 'underage', 'other')),
  details text check (char_length(details) <= 1000),
  created_at timestamptz not null default now()
);

alter table public.messages enable row level security;
alter table public.reports enable row level security;

create policy "read my conversations" on public.messages
  for select to authenticated using (auth.uid() in (user_a, user_b));

-- Reports are write-only for users; only the team reads them.
create policy "file reports" on public.reports
  for insert to authenticated with check (reporter = auth.uid());

-- Live updates for open chats (Supabase Realtime respects the select policy above).
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.messages;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Messaging
-- ---------------------------------------------------------------------------

create or replace function public.send_message(other uuid, body text)
returns public.messages
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  a uuid := least(me, other);
  b uuid := greatest(me, other);
  row public.messages;
begin
  if me is null then raise exception 'not signed in'; end if;
  if not exists (select 1 from public.matches where user_a = a and user_b = b) then
    raise exception 'you can only message people you matched with';
  end if;
  insert into public.messages (user_a, user_b, sender, body)
  values (a, b, me, btrim(body))
  returning * into row;
  return row;
end;
$$;

-- Newest last. Pass before_id to page back through older messages.
create or replace function public.get_messages(other uuid, before_id bigint default null, max_results int default 50)
returns setof public.messages
language sql
stable
security definer
set search_path = public
as $$
  select * from (
    select m.*
    from public.messages m
    where m.user_a = least(auth.uid(), other)
      and m.user_b = greatest(auth.uid(), other)
      and auth.uid() in (m.user_a, m.user_b)
      and (before_id is null or m.id < before_id)
    order by m.id desc
    limit least(max_results, 200)
  ) page
  order by id;
$$;

create or replace function public.mark_read(other uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.messages
  set read_at = now()
  where user_a = least(auth.uid(), other)
    and user_b = greatest(auth.uid(), other)
    and sender = other
    and read_at is null;
$$;

-- ---------------------------------------------------------------------------
-- Leaving a conversation
-- ---------------------------------------------------------------------------

-- Ends the match for both people and deletes the conversation. They won't reappear in the feed.
create or replace function public.unmatch_person(other uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  delete from public.matches where user_a = least(me, other) and user_b = greatest(me, other);
  delete from public.likes where (from_user = me and to_user = other) or (from_user = other and to_user = me);
  insert into public.passes (from_user, to_user) values (me, other) on conflict do nothing;
end;
$$;

-- Unmatches, then makes sure neither person ever sees the other again.
create or replace function public.block_person(other uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  perform public.unmatch_person(other);
  insert into public.blocks (blocker, blocked) values (me, other) on conflict do nothing;
end;
$$;

-- Reports also block, so the person reporting is never shown the other again.
create or replace function public.report_person(other uuid, reason text, details text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  insert into public.reports (reporter, reported, reason, details) values (me, other, reason, details);
  perform public.block_person(other);
end;
$$;

-- ---------------------------------------------------------------------------
-- Matches, now with the latest message and unread count
-- ---------------------------------------------------------------------------

drop function if exists public.get_matches();

create function public.get_matches()
returns table (
  person_id uuid,
  first_name text,
  age int,
  photo_paths text[],
  matched_at timestamptz,
  shared_places jsonb,
  last_message text,
  last_message_at timestamptz,
  last_message_mine boolean,
  unread int
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
         ), '[]'::jsonb),
         lm.body,
         lm.created_at,
         lm.sender = me,
         (select count(*)::int from public.messages u
          where u.user_a = mt.user_a and u.user_b = mt.user_b and u.sender = pr.id and u.read_at is null)
  from public.matches mt
  join public.profiles pr on pr.id = case when mt.user_a = me then mt.user_b else mt.user_a end
  left join lateral (
    select m.body, m.created_at, m.sender
    from public.messages m
    where m.user_a = mt.user_a and m.user_b = mt.user_b
    order by m.id desc
    limit 1
  ) lm on true
  where me in (mt.user_a, mt.user_b)
  order by coalesce(lm.created_at, mt.created_at) desc;
end;
$$;

revoke execute on function public.send_message(uuid, text) from public, anon;
revoke execute on function public.get_messages(uuid, bigint, int) from public, anon;
revoke execute on function public.mark_read(uuid) from public, anon;
revoke execute on function public.unmatch_person(uuid) from public, anon;
revoke execute on function public.block_person(uuid) from public, anon;
revoke execute on function public.report_person(uuid, text, text) from public, anon;
revoke execute on function public.get_matches() from public, anon;
grant execute on function public.send_message(uuid, text) to authenticated;
grant execute on function public.get_messages(uuid, bigint, int) to authenticated;
grant execute on function public.mark_read(uuid) to authenticated;
grant execute on function public.unmatch_person(uuid) to authenticated;
grant execute on function public.block_person(uuid) to authenticated;
grant execute on function public.report_person(uuid, text, text) to authenticated;
grant execute on function public.get_matches() to authenticated;
