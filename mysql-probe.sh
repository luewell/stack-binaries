#!/bin/sh
# Checks a repackaged MySQL: it initialises a data directory, serves on a
# socket and on 127.0.0.1, answers the client tools, and shuts down.
#
# Usage: mysql-probe.sh <mysql directory> <empty work directory> <version>
set -eu

root="$1"
work="$2"
expected_version="$3"
port=53306
data="$work/data"
socket="$work/mysqld.sock"
server_pid=""

finish() {
  status=$?
  if [ -n "$server_pid" ] && kill -0 "$server_pid" 2>/dev/null; then
    kill "$server_pid"
    wait "$server_pid" || true
  fi
  if [ "$status" -ne 0 ] && [ -f "$work/mysqld.log" ]; then
    cat "$work/mysqld.log" >&2
  fi
}
trap finish EXIT

mkdir -p "$work"

if ! "$root/bin/mysqld" --no-defaults --initialize-insecure \
  --basedir="$root" --datadir="$data" --log-error="$work/initialize.log"; then
  cat "$work/initialize.log" >&2
  exit 1
fi

"$root/bin/mysqld" --no-defaults --basedir="$root" --datadir="$data" \
  --bind-address=127.0.0.1 --port="$port" --mysqlx=OFF --socket="$socket" \
  --pid-file="$work/mysqld.pid" --log-error="$work/mysqld.log" &
server_pid=$!

ready=no
for _ in $(seq 1 120); do
  if "$root/bin/mysqladmin" --no-defaults --user=root --socket="$socket" ping >/dev/null 2>&1; then
    ready=yes
    break
  fi
  sleep 0.5
done
if [ "$ready" != yes ]; then
  echo "mysqld never answered on ${socket}" >&2
  exit 1
fi

answer="$("$root/bin/mysql" --no-defaults --user=root --socket="$socket" \
  --batch --skip-column-names -e 'select version()')"
if [ "$answer" != "$expected_version" ]; then
  echo "mysqld reports version '${answer}', expected ${expected_version}" >&2
  exit 1
fi

# mysqladmin ping succeeds once the server answers, whatever the account.
"$root/bin/mysqladmin" --no-defaults --user=root --host=127.0.0.1 --port="$port" \
  --protocol=TCP ping >/dev/null
"$root/bin/mysqldump" --no-defaults --user=root --socket="$socket" \
  --no-data --databases mysql >/dev/null

"$root/bin/mysqladmin" --no-defaults --user=root --socket="$socket" shutdown
wait "$server_pid"
server_pid=""
echo "MySQL ${answer} initialised, served on a socket and on 127.0.0.1, and shut down"
