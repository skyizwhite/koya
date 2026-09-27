# What the saved image needs

*2026-09-27*

## Context

A few lines in `koya-server/main` and `domain/timezone` exist only for the
executable that the Dockerfile saves, or for a system that has no zone
database. Their reasons were comments. `src/` has no comments now (see
[the spec comes first](2026-09-27-the-spec-comes-first-and-src-has-no-comments.md)),
and none of these cases can happen under `just spec`, so no spec can carry them
either. They are recorded here beside
[the image ADR](2026-09-23-the-image-is-published-and-runs-one-executable.md),
which already covers Woo and SIGTERM, the zone database's path and reading the
version when the server loads.

## Decision

- **`ironclad::*os-prng-stream*` is set to NIL before `save-lisp-and-die`.**
  Once ironclad has read from `/dev/urandom` it keeps the stream open. A stream
  saved in the image is dead in the next process.
- **`save-lisp-and-die` is given `:save-runtime-options t`.** The executable
  takes no command line, so SBCL must not parse one either. The heap size is
  the one the saving process was started with, which the Dockerfile sets.
- **clack's `:debug` is on only in dev mode.** With it on, an unhandled error
  invokes the debugger, and in a non-interactive image that ends the process.
  With it off, clack answers 500.
- **`find-timezone` checks that the zone repository has zones before it looks
  one up.** local-time's `find-timezone-by-location-name` signals an error on an
  empty repository, and a system without `/usr/share/zoneinfo` gives an empty
  one. Such a system offers UTC only.

## Consequences

Removing any of these still passes `just spec`, but breaks the image or a
system without a zone database. Before changing them, build the image and ask
it for `/health`.
