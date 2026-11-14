#!/bin/sh
# Copies from an extracted MySQL build what Stack runs: the server, the client
# tools it exposes, the plugins and bundled libraries they load, and the
# server's messages and character sets. The SQL --initialize runs is compiled
# into mysqld.
#
# Left out with the libraries only they load: the Kerberos, LDAP, SASL and FIDO
# authentication plugins, the telemetry plugins, which link the system's
# libcurl, and MeCab's full-text parser with its dictionaries. So are the debug
# builds, headers, client library, documentation and test suite.
#
# Usage: mysql-assemble.sh <extracted upstream build> <tree to create>
set -eu

upstream="$1"
root="$2"

mkdir -p "$root/bin" "$root/lib" "$root/share/licenses/mysql"

for program in mysqld mysql mysqldump mysqladmin mysql_tzinfo_to_sql; do
  cp "$upstream/bin/$program" "$root/bin/"
done

# The macOS build keeps libprotobuf beside mysqld and OpenSSL in lib/; the
# Linux build keeps every bundled library in lib/private.
find "$upstream/bin" -maxdepth 1 -name '*.dylib' -exec cp -P {} "$root/bin/" \;
find "$upstream/lib" -maxdepth 1 -name '*.dylib' -exec cp -P {} "$root/lib/" \;
cp -RP "$upstream/lib/plugin" "$root/lib/"
if [ -d "$upstream/lib/private" ]; then
  cp -RP "$upstream/lib/private" "$root/lib/"
fi
cp -RP "$upstream/share/." "$root/share/"
cp "$upstream/LICENSE" "$upstream/README" "$root/share/licenses/mysql/"

rm -rf "$root/share/aclocal" "$root/lib/plugin/debug"
for plugin in authentication_kerberos_client authentication_ldap_sasl_client \
  authentication_webauthn authentication_webauthn_client \
  component_telemetry telemetry_client libpluginmecab; do
  rm -f "$root/lib/plugin/$plugin.so"
done
find "$root/lib" \( -name 'libkrb5*' -o -name 'libk5crypto*' -o -name 'libgssapi_krb5*' \
  -o -name 'libcom_err*' -o -name 'libsasl2*' -o -name sasl2 -o -name 'libldap*' \
  -o -name 'liblber*' -o -name 'libfido2*' -o -name 'libmysqlclient*' \) \
  -prune -exec rm -rf {} +
