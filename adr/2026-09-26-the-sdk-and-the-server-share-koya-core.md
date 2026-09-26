# The SDK and the server share koya-core

*2026-09-26*

## Context

`src/` held two systems: `koya` in `src/sdk/`, and `koya-server` in
`src/server/`. The schema, JSON, time and ids both of them need were
`koya/core/...`, part of `koya`. So the server depended on the library a site
loads, although all it used of it was the core: the SDK's DSL and HTTP client
are for sites and change for their sake, and the server had no reason to be
downstream of them.

The library was also called `koya`, the name of the whole project, so a reader
could not tell from the name that it was the SDK and not the server.

koya is not in any registry and is at 0.x; the only people depending on the
system's name pull it with qlot and change one line.

## Decision

Three systems, one directory each under `src/`:

- `koya-core` in `src/core/` — the schema, validation, diff, JSON, name
  conversion, time and ULIDs. MIT.
- `koya-sdk` in `src/sdk/` — the schema DSL and the HTTP client, with
  `koya-core` re-exported from the `koya-sdk` package. MIT.
- `koya-server` in `src/server/` — AGPL.

`koya-sdk` and `koya-server` depend on `koya-core` and not on each other.
`tests/server/layers.lisp` fails if a file of the server imports from
`koya-sdk`.

The packages follow the systems: `koya` becomes `koya-sdk`, `koya/config` and
`koya/client` become `koya-sdk/config` and `koya-sdk/client`, and
`koya/core/...` becomes `koya-core/...`.

## Consequences

A site writes `koya-sdk` in its `:depends-on` and `koya-sdk:` before the SDK's
symbols. The repository is still `koya`, so the qlot line is unchanged.

The MIT part is `koya-core.asd`, `koya-sdk.asd`, `LICENSE-MIT`, `src/core/` and
`src/sdk/`; the list in `adr/2026-09-23-the-server-is-agpl-the-library-is-mit.md`
reads as those. A file moved into `src/server/` from either is the licensing
change that ADR describes.
