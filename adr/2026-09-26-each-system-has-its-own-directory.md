# Each system has its own directory

Superseded by adr/2026-09-26-the-sdk-and-the-server-share-koya-core.md

*2026-09-26*

## Context

The `koya` system's `:pathname` was `src/`, and `koya-server`'s was
`src/server/`, inside it. The files under `src/` were the MIT library except for
one directory, which was the AGPL server. Which licence a file was under could
only be read from the list in `adr/2026-09-23-the-server-is-agpl-the-library-is-mit.md`,
and the tree did not show it.

## Decision

The library moves to `src/sdk/` and the server stays in `src/server/`: `src/`
holds the two systems side by side and nothing else. `koya.asd`, `src/sdk/` and
`LICENSE-MIT` are the MIT part; the rest is AGPL, as before.

Only the directories move. The packages are still `koya`, `koya/core/...` and
`koya-server/...`, since a package-inferred system names its packages from the
path under its `:pathname`, not from the path under `src/`.

## Consequences

The licensing ADR's list of MIT files (`src/main.lisp`, `src/client.lisp`,
`src/config.lisp`, `src/core.lisp`, `src/core/`) now reads as `src/sdk/`. Which
files are MIT did not change.

A file moved between `src/sdk/` and `src/server/` is the licensing change that
ADR describes, and now shows as one in the diff.
