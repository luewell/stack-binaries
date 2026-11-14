#!/usr/bin/env bash
# Checks a detached OpenPGP signature against one pinned key.
#
# The key is fetched from keyserver.ubuntu.com by its full fingerprint, and the
# signature counts only when gpg reports it valid and made under that primary
# key. A keyserver answering with some other key therefore fails the check
# instead of being trusted: the fingerprint, reviewed in this repository, is
# the pin, and the keyserver only carries the key material.
#
# Usage: openpgp-check.sh <primary key fingerprint> <signature> <signed file>
set -euo pipefail

fingerprint="$1"
signature="$2"
signed_file="$3"

if [[ ! "$fingerprint" =~ ^[0-9A-F]{40}$ ]]; then
  echo "the fingerprint must be 40 upper-case hex digits" >&2
  exit 1
fi

GNUPGHOME="$(mktemp -d)"
export GNUPGHOME
trap 'rm -rf "$GNUPGHOME"' EXIT

curl -fsSL --proto '=https' --proto-redir '=https' --max-time 60 --retry 3 --retry-all-errors \
  -o "$GNUPGHOME/key.asc" \
  "https://keyserver.ubuntu.com/pks/lookup?op=get&options=mr&search=0x${fingerprint}"
gpg --batch --quiet --import "$GNUPGHOME/key.asc"

if ! status="$(gpg --batch --status-fd 1 --verify "$signature" "$signed_file" 2>"$GNUPGHOME/verify.log")"; then
  cat "$GNUPGHOME/verify.log" >&2
  echo "${signed_file##*/} does not carry a good signature" >&2
  exit 1
fi

# gpg reports a signature by an expired or revoked key as good but adds one of
# these lines; a release signed that way is not trusted.
if printf '%s\n' "$status" | awk '$2 ~ /^(EXPKEYSIG|REVKEYSIG|EXPSIG)$/ {found = 1} END {exit !found}'; then
  echo "${signed_file##*/} is signed by an expired or revoked key" >&2
  exit 1
fi

# VALIDSIG ends with the fingerprint of the primary key, whichever subkey signed.
signer="$(printf '%s\n' "$status" | awk '$2 == "VALIDSIG" {print $NF}')"
if [ "$signer" != "$fingerprint" ]; then
  echo "${signed_file##*/} is signed by ${signer:-no valid key}, not ${fingerprint}" >&2
  exit 1
fi
echo "${signed_file##*/} is signed by ${fingerprint}"
