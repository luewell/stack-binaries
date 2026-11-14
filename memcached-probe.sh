#!/usr/bin/env bash
# Checks a memcached build: it listens on 127.0.0.1 and answers the version
# command with the version it was built as.
#
# Usage: memcached-probe.sh <memcached directory> <version>
set -euo pipefail

root="$1"
expected_version="$2"
port=51211

"$root/bin/memcached" --listen=127.0.0.1 --port="$port" --udp-port=0 --memory-limit=16 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT

listening=no
for _ in $(seq 1 40); do
  if (exec 3<>"/dev/tcp/127.0.0.1/${port}") 2>/dev/null; then
    listening=yes
    break
  fi
  sleep 0.25
done
if [ "$listening" != yes ]; then
  echo "memcached never listened on 127.0.0.1:${port}" >&2
  exit 1
fi

exec 3<>"/dev/tcp/127.0.0.1/${port}"
printf 'version\r\n' >&3
IFS= read -r -t 5 answer <&3
exec 3>&-
answer="${answer%$'\r'}"

if [ "$answer" != "VERSION ${expected_version}" ]; then
  echo "memcached answered '${answer}', expected VERSION ${expected_version}" >&2
  exit 1
fi
echo "memcached ${expected_version} listened on 127.0.0.1 and answered the version command"
