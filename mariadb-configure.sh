#!/usr/bin/env bash
# Configures a MariaDB build that runs from any directory and loads nothing
# outside the base system.
#
# OpenSSL (as wolfSSL), PCRE2, zlib and fmt are compiled in. The engines and
# plugins that need further libraries or a cluster are left out: Galera,
# RocksDB, Mroonga, Spider, CONNECT, ColumnStore, OQGraph, S3, DuckDB, Videx,
# the compression providers, PAM and GSSAPI authentication, the cracklib and
# HashiCorp plugins, and mariabackup. libaio, liburing, libnuma, systemd and
# jemalloc are not looked for, so a build host that has them changes nothing.
#
# Bison is not looked for either: the source tarball carries the generated
# parsers, and the system's or Homebrew's would only regenerate them.
#
# Usage: mariadb-configure.sh <source directory> <build directory> [cmake arguments...]
set -euo pipefail

source_directory="$1"
build_directory="$2"
shift 2

cmake -S "$source_directory" -B "$build_directory" \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DINSTALL_LAYOUT=STANDALONE \
  -DCMAKE_INSTALL_PREFIX=/usr/local/mysql \
  -DINSTALL_MYSQLTESTDIR= \
  -DWITH_SSL=bundled \
  -DWITH_PCRE=bundled \
  -DWITH_ZLIB=bundled \
  -DWITH_LIBFMT=bundled \
  -DWITH_WSREP=OFF \
  -DWITH_UNIT_TESTS=OFF \
  -DWITH_MARIABACKUP=OFF \
  -DWITH_EMBEDDED_SERVER=OFF \
  -DWITH_SYSTEMD=no \
  -DWITH_NUMA=OFF \
  -DWITH_JEMALLOC=no \
  -DWITH_URING=OFF \
  -DWITH_LIBAIO=OFF \
  -DCMAKE_DISABLE_FIND_PACKAGE_URING=ON \
  -DCMAKE_DISABLE_FIND_PACKAGE_LIBAIO=ON \
  -DCMAKE_DISABLE_FIND_PACKAGE_BISON=ON \
  -DPLUGIN_ROCKSDB=NO \
  -DPLUGIN_MROONGA=NO \
  -DPLUGIN_SPIDER=NO \
  -DPLUGIN_CONNECT=NO \
  -DPLUGIN_COLUMNSTORE=NO \
  -DPLUGIN_OQGRAPH=NO \
  -DPLUGIN_S3=NO \
  -DPLUGIN_DUCKDB=NO \
  -DPLUGIN_VIDEX=NO \
  -DPLUGIN_PROVIDER_BZIP2=NO \
  -DPLUGIN_PROVIDER_LZ4=NO \
  -DPLUGIN_PROVIDER_LZMA=NO \
  -DPLUGIN_PROVIDER_LZO=NO \
  -DPLUGIN_PROVIDER_SNAPPY=NO \
  -DPLUGIN_AUTH_PAM=NO \
  -DPLUGIN_AUTH_PAM_V1=NO \
  -DPLUGIN_AUTH_GSSAPI=NO \
  -DPLUGIN_CRACKLIB_PASSWORD_CHECK=NO \
  -DPLUGIN_HASHICORP_KEY_MANAGEMENT=NO \
  -DPLUGIN_AWS_KEY_MANAGEMENT=NO \
  "$@"
