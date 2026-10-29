#!/bin/sh
# Checks a repackaged PostgreSQL: it initialises, starts, and a role that is
# not a superuser creates and uses pg_partman in the database it owns, as a
# Stack group role does.
#
# Usage: postgresql-probe.sh <postgresql directory> <empty data directory> <pg_partman version>
set -eu

root="$1"
data="$2"
expected_version="$3"
port=55432

"$root/bin/initdb" -D "$data" -U probe_admin --auth=trust --encoding=UTF8 --no-sync >/dev/null
"$root/bin/pg_ctl" -D "$data" -o "-p $port -c listen_addresses=127.0.0.1" -l "$data.log" -w start >/dev/null
trap '"$root/bin/pg_ctl" -D "$data" -w stop >/dev/null' EXIT

"$root/bin/psql" -h 127.0.0.1 -p "$port" -U probe_admin -d postgres -X -q -v ON_ERROR_STOP=1 \
  -c "CREATE ROLE app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE" \
  -c "CREATE DATABASE app OWNER app"

answer="$("$root/bin/psql" -h 127.0.0.1 -p "$port" -U app -d app -X -q -tA -v ON_ERROR_STOP=1 <<'SQL'
CREATE SCHEMA partman;
CREATE EXTENSION pg_partman SCHEMA partman;
CREATE TABLE events (id bigint, created_at timestamptz NOT NULL) PARTITION BY RANGE (created_at);
DO $$ BEGIN PERFORM partman.create_parent('public.events', 'created_at', '1 day'); END $$;
CALL partman.run_maintenance_proc();
INSERT INTO events VALUES (1, now());
SELECT extversion || ' ' || (SELECT count(*) FROM pg_inherits WHERE inhparent = 'public.events'::regclass)
  FROM pg_extension WHERE extname = 'pg_partman';
SQL
)"

version="${answer% *}"
partitions="${answer#* }"
if [ "$version" != "$expected_version" ] || [ "$partitions" -lt 2 ]; then
  echo "pg_partman answered '${answer}', expected ${expected_version} with partitions" >&2
  exit 1
fi
echo "pg_partman ${version} created ${partitions} partitions as a role that is not a superuser"
