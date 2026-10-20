-- Prompts, photo paths and likes on any part of a profile.

\set ON_ERROR_STOP on
set client_min_messages = warning;

insert into auth.users (id) values
  ('00000000-0000-0000-0000-000000000201'),
  ('00000000-0000-0000-0000-000000000202');

insert into public.profiles (id, first_name, birthday, gender, show_me, intent)
values ('00000000-0000-0000-0000-000000000201', 'Ada', date '1995-02-01', 'woman', 'everyone', 'dating'),
       ('00000000-0000-0000-0000-000000000202', 'Ben', date '1994-06-01', 'man', 'everyone', 'dating');

-- Ada and Ben share a café, so they see each other in the feed.
insert into public.places (user_id, place_key, cells, category, neighbourhood, venue_name, rhythm, visit_days)
select id, 'gcpvn0t', array['gcpvn0t'], 'Café', 'Hackney', 'Little Fern', 'Weekday mornings', 20
from auth.users where id in ('00000000-0000-0000-0000-000000000201', '00000000-0000-0000-0000-000000000202');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000201', false);
set role authenticated;
do $$
declare
  me uuid := '00000000-0000-0000-0000-000000000201';
  bad jsonb;
begin
  update public.profiles set prompts = '[
    {"q": "My third place is…", "a": "The lido at 8 am."},
    {"q": "A perfect Sunday", "a": "Long swim, longer breakfast."},
    {"q": "Green flag", "a": "You know the barista’s name."}
  ]' where id = me;
  assert (select jsonb_array_length(prompts) from public.profiles where id = me) = 3, 'three prompts save';

  foreach bad in array array[
    '[{"q": "a", "a": "1"}, {"q": "b", "a": "2"}, {"q": "c", "a": "3"}, {"q": "d", "a": "4"}]'::jsonb,
    '[{"q": "Same", "a": "1"}, {"q": "Same", "a": "2"}]',
    '[{"q": "Blank answer", "a": "   "}]',
    '[{"q": "Extra", "a": "x", "secret": true}]',
    '[{"q": "Missing answer"}]',
    '{"q": "Not a list", "a": "x"}',
    jsonb_build_array(jsonb_build_object('q', 'Too long', 'a', repeat('x', 201)))
  ] loop
    begin
      update public.profiles set prompts = bad where id = me;
      assert false, format('prompts %s should be refused', bad);
    exception when check_violation then null;
    end;
  end loop;

  update public.profiles set photo_paths = array[me::text || '/a.jpg', me::text || '/b.jpg'] where id = me;
  begin
    update public.profiles set photo_paths = array['00000000-0000-0000-0000-000000000202/0.jpg'] where id = me;
    assert false, 'someone else''s photo is refused';
  exception when check_violation then null;
  end;
  begin
    update public.profiles set photo_paths = array[me::text || '/../00000000-0000-0000-0000-000000000202/0.jpg'] where id = me;
    assert false, 'paths can''t climb out of the folder';
  exception when check_violation then null;
  end;
end $$;
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000202', false);
set role authenticated;
do $$
declare
  ada uuid := '00000000-0000-0000-0000-000000000201';
  row record;
begin
  select * into row from public.get_feed(10) where person_id = ada;
  assert found, 'Ada is in Ben''s feed';
  assert jsonb_array_length(row.prompts) = 3, 'the feed carries all three prompts';
  assert row.prompts -> 1 ->> 'q' = 'A perfect Sunday', 'prompts keep their order';

  begin
    perform public.like_person(ada, 'photo7');
    assert false, 'there is no seventh photo';
  exception when check_violation then null;
  end;
  assert (public.like_person(ada, 'prompt2') ->> 'ok')::boolean, 'a second prompt can be liked';
end $$;
reset role;

\echo 'Profile tests passed.'
