#!/bin/sh
# Checks a MariaDB build: it installs the system tables, serves on a socket and
# on 127.0.0.1, answers the client tools, and shuts down.
#
# Usage: mariadb-probe.sh <mariadb directory> <empty work directory> <version>
set -eu

root="$1"
work="$2"
expected_version="$3"
port=53307
data="$work/data"
socket="$work/mariadbd.sock"
server_pid=""

finish() {
  status=$?
  if [ -n "$server_pid" ] && kill -0 "$server_pid" 2>/dev/null; then
    kill "$server_pid"
    wait "$server_pid" || true
  fi
  if [ "$status" -ne 0 ] && [ -f "$work/mariadbd.log" ]; then
    cat "$work/mariadbd.log" >&2
  fi
}
trap finish EXIT

mkdir -p "$work"

if ! "$root/scripts/mariadb-install-db" --no-defaults --basedir="$root" --datadir="$data" \
  --auth-root-authentication-method=normal --skip-test-db >"$work/install.log" 2>&1; then
  cat "$work/install.log" >&2
  exit 1
fi

"$root/bin/mariadbd" --no-defaults --basedir="$root" --datadir="$data" \
  --bind-address=127.0.0.1 --port="$port" --socket="$socket" \
  --pid-file="$work/mariadbd.pid" --log-error="$work/mariadbd.log" &
server_pid=$!

ready=no
for _ in $(seq 1 120); do
  if "$root/bin/mariadb-admin" --no-defaults --user=root --socket="$socket" ping >/dev/null 2>&1; then
    ready=yes
    break
  fi
  sleep 0.5
done
if [ "$ready" != yes ]; then
  echo "mariadbd never answered on ${socket}" >&2
  exit 1
fi

answer="$("$root/bin/mariadb" --no-defaults --user=root --socket="$socket" \
  --batch --skip-column-names -e 'select version()')"
case "$answer" in
  "$expected_version"-MariaDB*) ;;
  *)
    echo "mariadbd reports version '${answer}', expected ${expected_version}" >&2
    exit 1
    ;;
esac

# mariadb-admin ping succeeds once the server answers, whatever the account.
"$root/bin/mariadb-admin" --no-defaults --user=root --host=127.0.0.1 --port="$port" \
  --protocol=TCP ping >/dev/null
"$root/bin/mariadb-dump" --no-defaults --user=root --socket="$socket" \
  --no-data --databases mysql >/dev/null

"$root/bin/mariadb-admin" --no-defaults --user=root --socket="$socket" shutdown
wait "$server_pid"
server_pid=""
echo "MariaDB ${answer} installed, served on a socket and on 127.0.0.1, and shut down"
