# The image runs one saved executable

*2026-09-27, restating a decision of 2026-09-23*

## Context

An image that is the build environment holds SBCL, Quicklisp and every source,
`build-essential` and the Tailwind binary, and loads the server on every start.

## Decision

- The Dockerfile has two stages. The build stage loads `koya-server` and saves
  it with `koya-server:save-executable`, which calls `save-lisp-and-die` with
  `koya-server:main` as the toplevel.
- The runtime stage is `debian:bookworm-slim`, the build image's Debian, so the
  shared libraries SBCL reopens are the same. It holds the executable,
  `assets/` and the C libraries it opens, and nothing to build with.

## Consequences

- An image starts serving in about a second.
- Whatever a library resolves when it loads is resolved on the build stage, so
  it must not name a place only that stage has. `domain/timezone` reads the
  system's `/usr/share/zoneinfo`, and `/admin/api/me` reads the version when it
  loads instead of asking ASDF.
- A `.env` is read when the server loads, and `.dockerignore` keeps it out of
  the build, so the image takes its settings from the environment.
