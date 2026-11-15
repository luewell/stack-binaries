#!/usr/bin/env bash
# Fetches the pinned source of each extension below that a craft file lists,
# refuses any whose sha256 differs, and appends download-options to the craft
# file so static-php-cli takes these files instead of resolving its own.
#
# static-php-cli takes the newest release of each from PECL or Packagist and
# checks no digest; Packagist's first xdebug entry is 3.6.0alpha1. Each pin is
# the newest stable release published at least 14 days before it was chosen,
# and its sha256 is of the file at that URL.
#
# Prints "<extension> <version>" for each fetched source, the version the
# extension reports through phpversion().
#
# Usage: php-extension-sources.sh <craft file> <PHP release> <directory>
set -euo pipefail

craft="$1"
php_version="$2"
directory="$3"

# Xdebug 3.5 supports PHP 8.2 to 8.5 and 3.4 is the last for 8.1, per
# https://xdebug.org/docs/compat. Both PECL and xdebug.org serve the same bytes.
case "$php_version" in
  8.1.*)
    xdebug_version="3.4.7"
    xdebug_sha256="7592923501e3fdb9741ad35b90e08fc6b3c5dd31eadc4c83b7b3c9dda0627b24"
    ;;
  8.2.* | 8.3.* | 8.4.* | 8.5.*)
    xdebug_version="3.5.3"
    xdebug_sha256="f073de91bea046106abf4d6071c963ea71e58571df6ce58948ceca89d121cb2d"
    ;;
  *)
    echo "no Xdebug release is pinned for PHP ${php_version}" >&2
    exit 1
    ;;
esac

# extension, version, URL, sha256 and file name. spx publishes nothing but
# GitHub's archive of its tag, the source static-php-cli's Packagist entry
# points at. opentelemetry 1.5.0 came out on 2026-11-09, too recent to take.
pins="
xdebug ${xdebug_version} https://pecl.php.net/get/xdebug-${xdebug_version}.tgz ${xdebug_sha256} xdebug-${xdebug_version}.tgz
pcov 1.0.12 https://pecl.php.net/get/pcov-1.0.12.tgz 23255c8c9335a9636ccb743f5302436a97a582a0bbde9869485be911bbc15da8 pcov-1.0.12.tgz
spx 0.4.22 https://github.com/NoiseByNorthwest/php-spx/archive/refs/tags/v0.4.22.tar.gz 6f89addd100d3d71168c094612eb8e1c06fd8062da6ee4d9df5b31bdfc4de160 php-spx-0.4.22.tar.gz
memcached 3.4.0 https://pecl.php.net/get/memcached-3.4.0.tgz c163434eb0da97c8f45c7ad41d979d381f8b81c49402b1b90b063987fb37972e memcached-3.4.0.tgz
opentelemetry 1.4.2 https://pecl.php.net/get/opentelemetry-1.4.2.tgz a355329259f373c5c7327e66310481726cfabac50cb5483eba000bec791d5017 opentelemetry-1.4.2.tgz
"

digest_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

if grep -q '^download-options:' "$craft"; then
  echo "${craft} already has download-options, which this would duplicate" >&2
  exit 1
fi

mkdir -p "$directory"
directory="$(cd "$directory" && pwd -P)"

# static-php-cli fetches a custom URL with curl, which reads file:// as well.
# On Windows the path must be D:/..., which curl takes after file:///.
local_directory="$directory"
if command -v cygpath >/dev/null 2>&1; then
  local_directory="$(cygpath -m "$directory")"
fi
case "$local_directory" in
  /*) base_url="file://${local_directory}" ;;
  *) base_url="file:///${local_directory}" ;;
esac
if [[ ! "$base_url" =~ ^file:///[A-Za-z0-9/._:-]+$ ]]; then
  echo "${directory} cannot be written into craft.yml as it is" >&2
  exit 1
fi

custom_urls=""
while read -r extension version url sha256 filename; do
  [ -n "$extension" ] || continue
  grep -qx "  - ${extension}" "$craft" || continue

  curl -fsSL --proto '=https' --proto-redir '=https' --retry 3 -o "${directory}/${filename}" "$url"
  actual="$(digest_of "${directory}/${filename}")"
  if [ "$actual" != "$sha256" ]; then
    echo "${url} is not what we pinned:" >&2
    echo "  expected ${sha256}" >&2
    echo "  got      ${actual}" >&2
    exit 1
  fi

  custom_urls="${custom_urls}    - \"${extension}:${base_url}/${filename}\""$'\n'
  echo "${extension} ${version}"
done <<< "$pins"

if [ -n "$custom_urls" ]; then
  printf 'download-options:\n  custom-url:\n%s' "$custom_urls" >> "$craft"
fi
