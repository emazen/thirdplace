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
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f tests/backend_test.sql
dropdb "$DB"

# Second pass: the demo seed, as a newcomer would see it.
createdb "$DB"
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f tests/local_supabase_stub.sql
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f migrations/20261018120000_core.sql
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f seed.sql
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f tests/seed_test.sql
dropdb "$DB"
