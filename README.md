# stack-binaries

Prebuilt binaries for [stack](https://github.com/luewell/stack), for the few
things upstream does not publish for a platform we support.

Everything here is built from public sources by the workflows in this
repository, on GitHub's own runners, and published as a release with its
SHA-256. Nothing is uploaded from anybody's machine.

## Why this exists

`stack` never compiles on a developer's machine: the people using it have small
laptops, and a build is minutes of their time and heat for something a server
can do once. So where a project ships no binary for a platform, the cost moves
here.

## What is here

| | |
|---|---|
| **Valkey for macOS** | Valkey publishes Linux builds for Ubuntu noble and nothing else, and its GitHub releases carry no binaries at all. BSD-3, so redistributing a build is a fact rather than a question. |

## How a release is used

A release's SHA-256 is copied by hand into the catalogue entry that points at
it. The digest is pinned there rather than fetched, because an entry that
fetched its own checksum would be verifying a download against a value from the
same place it came from.

## Building

Each workflow runs on request, for a version you name. It refuses to publish a
binary that would only work where it was built: a library path naming the build
machine means the binary can be installed in one directory for ever, which is
how DBngin ends up pinned to `/Users/Shared/DBngin`.
