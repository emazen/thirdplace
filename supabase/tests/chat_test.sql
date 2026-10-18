-- Chat, unmatch, block and report. Runs after backend_test.sql's setup, on its own database.
\set ON_ERROR_STOP on
set client_min_messages = warning;

insert into auth.users (id) values
  ('00000000-0000-0000-0000-0000000000c1'),
  ('00000000-0000-0000-0000-0000000000c2'),
  ('00000000-0000-0000-0000-0000000000c3');
insert into public.profiles (id, first_name, birthday, gender, show_me, intent) values
  ('00000000-0000-0000-0000-0000000000c1', 'Ada',  '1995-01-01', 'woman', 'everyone', 'both'),
  ('00000000-0000-0000-0000-0000000000c2', 'Ben',  '1994-01-01', 'man',   'everyone', 'both'),
  ('00000000-0000-0000-0000-0000000000c3', 'Cleo', '1996-01-01', 'woman', 'everyone', 'both');
-- Ada and Ben match. Cleo matches no one.
insert into public.matches (user_a, user_b) values ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000c2');
insert into public.likes (from_user, to_user, item) values
  ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000c2', 'first'),
  ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000c1', 'first');

-- Ada writes to Ben.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', false);
set role authenticated;
do $$
begin
  perform public.send_message('00000000-0000-0000-0000-0000000000c2', '  Same café, right?  ');
  perform public.send_message('00000000-0000-0000-0000-0000000000c2', 'The one with the green door.');
  assert (select count(*) from public.get_messages('00000000-0000-0000-0000-0000000000c2')) = 2, 'two messages';
  assert (select body from public.get_messages('00000000-0000-0000-0000-0000000000c2') limit 1) = 'Same café, right?', 'oldest first, trimmed';

  begin
    perform public.send_message('00000000-0000-0000-0000-0000000000c3', 'hi');
    assert false, 'no messages without a match';
  exception when raise_exception then null;
  end;

  begin
    insert into public.messages (user_a, user_b, sender, body)
    values ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000c2', auth.uid(), 'sneaky');
    assert false, 'messages only go through send_message()';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- Ben sees them as unread, replies, and reads.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c2', false);
set role authenticated;
do $$
begin
  assert (select unread from public.get_matches() where first_name = 'Ada') = 2, 'two unread';
  assert (select last_message from public.get_matches() where first_name = 'Ada') = 'The one with the green door.', 'latest message shown';
  perform public.mark_read('00000000-0000-0000-0000-0000000000c1');
  assert (select unread from public.get_matches() where first_name = 'Ada') = 0, 'read';
  perform public.send_message('00000000-0000-0000-0000-0000000000c1', 'Yes! Thursday mornings?');
  assert (select last_message_mine from public.get_matches() where first_name = 'Ada'), 'my reply is the latest';
end $$;
reset role;

-- Cleo can't read their conversation.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c3', false);
set role authenticated;
do $$
begin
  assert (select count(*) from public.messages) = 0, 'outsiders see nothing';
  assert (select count(*) from public.get_messages('00000000-0000-0000-0000-0000000000c1')) = 0, 'not even through the function';
end $$;
reset role;

-- Ada unmatches: the conversation is gone for both, and Ben stays out of her feed.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', false);
set role authenticated;
do $$
begin
  perform public.unmatch_person('00000000-0000-0000-0000-0000000000c2');
  assert (select count(*) from public.get_matches()) = 0, 'match gone';
  assert (select count(*) from public.messages) = 0, 'conversation gone';
  assert exists (select 1 from public.passes where to_user = '00000000-0000-0000-0000-0000000000c2'), 'kept out of the feed';
end $$;
reset role;

-- Cleo reports Ada: a report is filed and Cleo has blocked her.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c3', false);
set role authenticated;
select public.report_person('00000000-0000-0000-0000-0000000000c1', 'fake', 'Photos look stolen');
do $$
begin
  assert (select count(*) from public.reports) = 0, 'reporters can''t read reports back';
  assert exists (select 1 from public.blocks where blocked = '00000000-0000-0000-0000-0000000000c1'), 'report also blocks';
end $$;
reset role;
do $$
begin
  assert (select count(*) from public.reports where reason = 'fake') = 1, 'report stored';
end $$;

\echo 'Chat tests passed.'
