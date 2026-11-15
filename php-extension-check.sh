#!/usr/bin/env bash
# Checks that a PHP build carries spx, memcached and opentelemetry, that it
# loads xdebug.so and pcov.so from the given directory, that every extension
# reports the version php-extension-sources.sh pinned, and that pcov collects
# coverage.
#
# Usage: php-extension-check.sh <php> <extension directory> <versions file>
set -euo pipefail

php="$1"
extension_directory="$(cd "$2" && pwd -P)"
versions="$3"

xdebug="${extension_directory}/xdebug.so"
pcov="${extension_directory}/pcov.so"
loaded=(-d "zend_extension=${xdebug}" -d "extension=${pcov}")

# Resolved, since pcov.directory is compared with the real path of each file
# and macOS's temporary directory is reached through the /var symlink.
scratch="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$scratch"' EXIT

"$php" "${loaded[@]}" -m | tr '[:upper:]' '[:lower:]' | sort -u > "${scratch}/modules"
missing=""
for extension in spx memcached opentelemetry xdebug pcov; do
  grep -qx "$extension" "${scratch}/modules" || missing="${missing} ${extension}"
done
if [ -n "$missing" ]; then
  echo "${php} with ${extension_directory} is missing:${missing}" >&2
  "$php" "${loaded[@]}" -m >&2
  exit 1
fi

# A version other than the pin means static-php-cli took a source of its own.
checked=0
while read -r extension expected; do
  [ -n "$extension" ] || continue
  if [[ ! "$extension" =~ ^[a-z_]+$ ]]; then
    echo "${versions} names ${extension}, which is not an extension name" >&2
    exit 1
  fi
  actual="$("$php" "${loaded[@]}" -r "echo phpversion('${extension}');")"
  if [ "$actual" != "$expected" ]; then
    echo "${extension} reports ${actual:-no version}, where ${expected} was pinned" >&2
    exit 1
  fi
  echo "${extension} ${actual}"
  checked=$((checked + 1))
done < "$versions"
if [ "$checked" -ne 5 ]; then
  echo "${versions} names ${checked} extensions, not the five this checks" >&2
  exit 1
fi

# pcov reports executed lines as 1 and executable lines not run as -1.
cat > "${scratch}/doubled.php" <<'PHP'
<?php
function doubled(int $value): int
{
    if ($value > 0) {
        return $value * 2;
    }

    return 0;
}
PHP

# shellcheck disable=SC2016 # PHP code, whose variables PHP expands.
COVERED_FILE="${scratch}/doubled.php" "$php" -d "extension=${pcov}" -d pcov.enabled=1 \
  -d "pcov.directory=${scratch}" -r '
    $file = realpath(getenv("COVERED_FILE"));
    \pcov\start();
    require $file;
    doubled(2);
    \pcov\stop();
    $lines = \pcov\collect()[$file] ?? [];
    if (!in_array(1, $lines, true) || !in_array(-1, $lines, true)) {
      fwrite(STDERR, "pcov collected no usable coverage of {$file}" . PHP_EOL);
      var_dump(\pcov\collect());
      exit(1);
    }
    echo "pcov collected coverage of ", count($lines), " lines", PHP_EOL;
  '
