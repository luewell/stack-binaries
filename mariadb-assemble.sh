#!/bin/sh
# Copies from an installed MariaDB build what Stack runs: the server, the
# client tools it exposes, mariadb-install-db with the two programs it calls,
# the plugins, the client library, and the server's messages, character sets
# and system-table SQL.
#
# Usage: mariadb-assemble.sh <installation prefix> <tree to create>
set -eu

installed="$1"
root="$2"

mkdir -p "$root/bin" "$root/scripts" "$root/lib" "$root/share/licenses/mariadb"

for program in mariadbd mariadb mariadb-dump mariadb-admin mariadb-tzinfo-to-sql \
  my_print_defaults resolveip; do
  cp "$installed/bin/$program" "$root/bin/"
done
cp "$installed/scripts/mariadb-install-db" "$root/scripts/"

cp -RP "$installed/lib/plugin" "$root/lib/"
find "$installed/lib" -maxdepth 1 \( -name 'libmariadb.so*' -o -name 'libmariadb*.dylib' \) \
  -exec cp -P {} "$root/lib/" \;
cp -RP "$installed/share/." "$root/share/"

cp "$installed/COPYING" "$installed/THIRDPARTY" "$root/share/licenses/mariadb/"
