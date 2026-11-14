#!/usr/bin/env bash
# Checks that every binary in a packaged tree loads only libraries of the base
# system or files inside the tree, so the tree runs from whatever directory
# Stack installs it in.
#
# On macOS, a dependency must be under /usr/lib or /System/Library, or be found
# through @loader_path, @executable_path or @rpath inside the tree. On Linux, a
# run path must start at $ORIGIN, a dependency must resolve inside the tree or
# be one every supported distribution installs, the executables in bin/ must
# bind every symbol, and nothing may ask for a glibc newer than Ubuntu 22.04's.
#
# Usage: relocatable-check.sh <tree>
set -euo pipefail

root="$(cd "$1" && pwd -P)"
failures=0
checked=0

# glibc and the GCC runtime, plus zlib, libxcrypt and libtinfo, which dpkg,
# libc6 and bash depend on, so no Debian or Ubuntu installation lacks them.
linux_system_library='^(linux-vdso\.so\.1|ld-linux-(x86-64|aarch64)\.so\.[0-9]+|libc\.so\.6|libm\.so\.6|libdl\.so\.2|libpthread\.so\.0|librt\.so\.1|libresolv\.so\.2|libutil\.so\.1|libstdc\+\+\.so\.6|libgcc_s\.so\.1|libz\.so\.1|libcrypt\.so\.1|libtinfo\.so\.6)$'
glibc_ceiling="2.35"

fail() {
  echo "$1" >&2
  failures=$((failures + 1))
}

magic_of() {
  od -An -tx1 -N4 "$1" | tr -d ' \n'
}

macos_rpaths_of() {
  otool -l "$1" | awk '$1 == "cmd" { in_rpath = ($2 == "LC_RPATH") } in_rpath && $1 == "path" { print $2 }'
}

macos_expand() {
  local entry="$1"
  local loader_dir="$2"
  case "$entry" in
    @loader_path*) printf '%s\n' "${loader_dir}${entry#@loader_path}" ;;
    @executable_path*) printf '%s\n' "${root}/bin${entry#@executable_path}" ;;
    *) printf '%s\n' "$entry" ;;
  esac
}

executable_rpaths=""
if [ "$(uname -s)" = Darwin ] && [ -d "$root/bin" ]; then
  while IFS= read -r -d '' executable; do
    if [ "$(magic_of "$executable")" = cffaedfe ]; then
      while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        executable_rpaths="${executable_rpaths}$(macos_expand "$entry" "$root/bin")"$'\n'
      done <<< "$(macos_rpaths_of "$executable")"
    fi
  done < <(find "$root/bin" -maxdepth 1 -type f -print0)
fi

check_macho() {
  local file="$1"
  local directory own_id own_rpaths entry dependency candidate found
  directory="$(dirname "$file")"
  own_id="$(otool -D "$file" | sed -n 2p)"
  own_rpaths="$(macos_rpaths_of "$file")"

  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    case "$entry" in
      @loader_path|@loader_path/*|@executable_path|@executable_path/*) ;;
      *) fail "${file#"$root"/} searches ${entry}, outside the tree" ;;
    esac
  done <<< "$own_rpaths"

  while IFS= read -r dependency; do
    [ -n "$dependency" ] || continue
    [ "$dependency" != "$own_id" ] || continue
    case "$dependency" in
      /usr/lib/*|/System/Library/*) ;;
      @loader_path/*|@executable_path/*)
        candidate="$(macos_expand "$dependency" "$directory")"
        [ -e "$candidate" ] || fail "${file#"$root"/} needs ${dependency}, which is not in the tree"
        ;;
      @rpath/*)
        found=no
        while IFS= read -r entry; do
          [ -n "$entry" ] || continue
          candidate="$(macos_expand "$entry" "$directory")/${dependency#@rpath/}"
          if [ -e "$candidate" ]; then
            found=yes
            break
          fi
        done <<< "${own_rpaths}"$'\n'"${executable_rpaths}"
        [ "$found" = yes ] || fail "${file#"$root"/} needs ${dependency}, which no run path finds in the tree"
        ;;
      *) fail "${file#"$root"/} links against ${dependency}, outside the system and the tree" ;;
    esac
  done <<< "$(otool -L "$file" | tail -n +2 | grep -v ':$' | awk '{print $1}')"
}

check_elf() {
  local file="$1"
  local run_paths entry ldd_output line name path resolved newest
  run_paths="$(readelf -d "$file" | sed -n 's/.*(\(RPATH\|RUNPATH\)).*\[\(.*\)\]$/\2/p')"
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    # shellcheck disable=SC2016 # $ORIGIN is matched literally, as the loader reads it.
    case "$entry" in
      '$ORIGIN'|'$ORIGIN/'*) ;;
      *) fail "${file#"$root"/} searches ${entry}, which is not relative to \$ORIGIN" ;;
    esac
  done <<< "$(printf '%s\n' "$run_paths" | tr ':' '\n')"

  if ! ldd_output="$(ldd "$file" 2>&1)"; then
    case "$ldd_output" in
      *"not a dynamic executable"*) return ;;
      *) fail "ldd cannot read ${file#"$root"/}: ${ldd_output}"; return ;;
    esac
  fi
  case "$ldd_output" in
    *"statically linked"*) return ;;
  esac

  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"
    [ -n "$line" ] || continue
    name="${line%% *}"
    case "$line" in
      *"=> not found"*)
        fail "${file#"$root"/} needs ${name}, which is nowhere"
        ;;
      *" => "*)
        path="${line#* => }"
        path="${path%% (*}"
        resolved="$(readlink -f "$path")"
        case "$resolved" in
          "$root"/*) ;;
          *)
            [[ "$name" =~ $linux_system_library ]] \
              || fail "${file#"$root"/} loads ${name} from ${path}, which is outside the tree and not in every base system"
            ;;
        esac
        ;;
      *)
        [[ "${name##*/}" =~ $linux_system_library ]] \
          || fail "${file#"$root"/} loads ${name}, which is not in every base system"
        ;;
    esac
  done <<< "$ldd_output"

  if [ "$(dirname "$file")" = "$root/bin" ] && ldd -r "$file" 2>&1 | grep -q 'undefined symbol'; then
    fail "${file#"$root"/} leaves symbols unbound:"
    ldd -r "$file" 2>&1 | grep 'undefined symbol' >&2
  fi

  newest="$(objdump -T "$file" | grep -oE 'GLIBC_[0-9]+\.[0-9]+(\.[0-9]+)?' | sed 's/^GLIBC_//' | sort -V | tail -n 1)"
  if [ -n "$newest" ] && [ "$(printf '%s\n%s\n' "$newest" "$glibc_ceiling" | sort -V | tail -n 1)" != "$glibc_ceiling" ]; then
    fail "${file#"$root"/} needs glibc ${newest}, newer than Ubuntu 22.04's ${glibc_ceiling}"
  fi
}

while IFS= read -r -d '' file; do
  case "$(magic_of "$file")" in
    cffaedfe)
      check_macho "$file"
      checked=$((checked + 1))
      ;;
    7f454c46)
      check_elf "$file"
      checked=$((checked + 1))
      ;;
  esac
done < <(find "$root" -type f -print0)

if [ "$checked" -eq 0 ]; then
  echo "found no binary under ${root}" >&2
  exit 1
fi
if [ "$failures" -gt 0 ]; then
  echo "${failures} problems in ${checked} binaries under ${root}" >&2
  exit 1
fi
echo "${checked} binaries under ${root} load only the base system and the tree"
