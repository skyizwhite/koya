# The image is published to GHCR and runs one executable

*2026-09-23*

## Context

koya could only be run by building the repository's Dockerfile (#3), and that
image was the build environment itself: SBCL, Quicklisp and every source,
`build-essential`, the Tailwind binary, and an entrypoint that `quickload`ed the
server on every start.

## Decision

- **Published** as `ghcr.io/skyizwhite/koya` by a workflow: a `v*` tag gives
  `X.Y.Z`, `X.Y` and `latest`, `master` gives `edge`. `linux/amd64` and
  `linux/arm64` are each built on a runner of that architecture, not under
  emulation, and each is started and asked for `/health` before it is pushed.
- **Two stages.** The build stage loads `koya-server` and saves it with
  `save-lisp-and-die` as an executable whose toplevel is `koya-server:main`. The
  runtime stage is `debian:bookworm-slim` — the build image's Debian, so the
  shared libraries SBCL reopens are the same — with that executable, `assets/`
  and the C libraries it opens.
- **The dependency layer is not split from the sources.** `qlot install` with
  only `qlfile`, `qlfile.lock` and the `.asd` files installs the locked dists
  but not every release the systems load: koya is package-inferred, so what it
  needs is only known from the sources.
- **Woo runs in `main`'s own thread.** Woo handles SIGTERM itself by leaving its
  loop; in a thread of its own it would leave `main` asleep, and `docker stop`
  would end in SIGKILL. Now `main` closes the database and exits.

## Consequences

An image starts serving in about a second and holds nothing to build with.
Whatever a library resolves when it loads is resolved on the build stage, so it
must not name a place only that stage has: local-time's zone database was one,
and `lib/timezone` now reads the system's `/usr/share/zoneinfo`; `/admin/api/me`
reads the version when it loads instead of asking ASDF. A `.env` is not read by
the image; it takes its settings from the environment.

Every change to the sources still rebuilds the dependency layer.
