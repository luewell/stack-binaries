# stack-binaries

Prebuilt binaries for [stack](https://github.com/luewell/stack): its own
releases, and the few things upstream does not publish for a platform we
support.

What upstream does not publish is built from public sources by the workflows in
this repository, on GitHub's own runners, and each archive's SHA-256 is printed
by the job that built it. Stack's own releases are the exception: they are built
and uploaded from the maintainer's machine, and
[below](#stacks-own-releases) is what makes that safe to take.

## Why this exists

`stack` never compiles on a developer's machine: the people using it have small
laptops, and a build is minutes of their time and heat for something a server
can do once. So where a project ships no binary for a platform, the cost moves
here.

## What is here

| | |
|---|---|
| **Stack** | The CLI itself, for macOS arm64 and Linux amd64 and arm64, released as `stack-<version>`. |
| **Valkey for macOS** | Valkey publishes Linux builds for Ubuntu noble and nothing else, and its GitHub releases carry no binaries at all. BSD-3, so redistributing a build is a fact rather than a question. |
| **Valkey for Windows** | Nobody publishes one, and Valkey does not build natively there. It builds against MSYS2's POSIX runtime, which emulates the fork and unix sockets it needs, with `_GNU_SOURCE` for `dladdr`; the archive carries that runtime's `msys-2.0.dll` (Cygwin, LGPL-3.0) and `msys-gcc_s-seh-1.dll`, with a notice naming their exact packages and sources. x64 only, which Windows on ARM runs emulated. Released as `valkey-<version>-windows`, since a published release takes no new asset. |
| **PHP** | Built with static-php-cli for macOS arm64 and Linux amd64 and arm64, because the public static builds leave out `pdo_pgsql` and `pdo_mysql`. |
| **PHP for Windows** | Built with static-php-cli too, with the same extensions but `pcntl` and `posix`, which exist only on Unix: the official Windows builds load each extension from a DLL a `php.ini` must name, and carry no `redis`. Windows has no php-fpm, so the archive carries `php-cgi.exe`, which serves FastCGI there. static-php-cli links `pgsql` against the `libpq.dll` of EnterpriseDB's PostgreSQL binaries, so that DLL and those it loads ship beside `php.exe`, named in `NOTICE-libraries.txt`; they need the Visual C++ runtime, as the official PHP builds do, which the archive does not carry. x64 only, which Windows on ARM runs emulated. Released as `php-<version>-windows` beside the version's own release. |
| **Ruby for Windows** | RubyInstaller's own relocatable build, unchanged, repacked from its 7z into a zip, which Stack extracts: it extracts no 7z. The upstream archives' digests are pinned in `ruby-windows-upstream.json`, checked against both rubyinstaller.org's downloads page and the digest GitHub records, and a repacked zip holds exactly the upstream tree, byte-for-byte the same when rebuilt on the same runner image. x64 and ARM64, x64 alone where RubyInstaller built no ARM64. Released as `ruby-<version>-windows`. |
| **PostgreSQL for Linux** | `theseus-rs/postgresql-binaries`' own build, unchanged, with a `libxml2.so.2` built from libxml2's release added to `lib/`: it links that library, which Ubuntu 26.04 replaced with the incompatible `libxml2.so.16`. The upstream archives' digests are pinned in `postgresql-upstream.json`, and a repackaged archive is byte-for-byte the same when rebuilt in the same Debian 12 image. |

## How a release is used

A workflow release's SHA-256 is copied by hand into the catalogue entry that
points at it. The digest is pinned there rather than fetched, because an entry
that fetched its own checksum would be verifying a download against a value from
the same place it came from. Stack's Homebrew formula likewise pins each archive
to its line in the release's `SHA256SUMS`.

## Building

Each workflow runs on request, for a version you name. It refuses to publish a
binary that would only work where it was built: a library path naming the build
machine means the binary can be installed in one directory for ever, which is
how DBngin ends up pinned to `/Users/Shared/DBngin`.

## Stack's own releases

`scripts/publish.sh` in the stack repository publishes them, with the
maintainer's own `gh` login rather than a token handed to the stack repository's
CI. It builds only a clean checkout whose version tag names the same commit
locally and on GitHub, and only once that tag's CI run has passed. The build is
reproducible: `-trimpath` binaries in canonical archives, so building the same
commit again gives the same bytes.

A release is exactly three archives, `SHA256SUMS` and the `SOURCE_COMMIT` they
were built from. Each archive is checked against `SHA256SUMS` before anything is
uploaded, and after the upload what the release serves is downloaded again and
compared byte for byte with the fresh build. Releases in this repository are
immutable, and the script refuses to publish until that is switched on, so once
a version is out its bytes cannot be replaced. Publishing a version again builds
it afresh and only confirms that what is out there still matches.
