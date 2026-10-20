#!/bin/sh
# Runs the migrations and backend tests against a throwaway database on local Postgres.
# Usage: supabase/tests/run-local.sh
set -e
cd "$(dirname "$0")/.."
DB=thirdplace_test

dropdb --if-exists "$DB"
createdb "$DB"
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f tests/local_supabase_stub.sql
# The storage migration needs Supabase's storage schema, so it only runs on a real project.
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f migrations/20261018120000_core.sql
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f migrations/20261018130000_chat.sql
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f migrations/20261020120000_prompts.sql
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f tests/backend_test.sql
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f tests/chat_test.sql
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f tests/profile_test.sql
dropdb "$DB"

# Second pass: the demo seed, as a newcomer would see it.
createdb "$DB"
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f tests/local_supabase_stub.sql
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f migrations/20261018120000_core.sql
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f migrations/20261018130000_chat.sql
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f migrations/20261020120000_prompts.sql
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f seed.sql
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f tests/seed_test.sql
dropdb "$DB"

# Third pass: a profile from before prompts became a list keeps its one prompt.
createdb "$DB"
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f tests/local_supabase_stub.sql
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f migrations/20261018120000_core.sql
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f migrations/20261018130000_chat.sql
psql -q -v ON_ERROR_STOP=1 -d "$DB" -c "insert into auth.users (id) values ('00000000-0000-0000-0000-000000000301');
  insert into public.profiles (id, first_name, birthday, gender, show_me, intent, prompt_question, prompt_answer)
  values ('00000000-0000-0000-0000-000000000301', 'Old', '1990-01-01', 'man', 'everyone', 'both', 'Green flag', 'Kind to waiters. ');"
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f migrations/20261020120000_prompts.sql
psql -q -v ON_ERROR_STOP=1 -d "$DB" -c "do \$\$ begin
  assert (select prompts from public.profiles where first_name = 'Old') = '[{\"q\": \"Green flag\", \"a\": \"Kind to waiters.\"}]'::jsonb, 'old prompt carried over';
end \$\$;"
dropdb "$DB"
echo "Upgrade test passed."
