# The SDK and the server share koya-core, and do not use each other

*2026-09-27, restating a decision of 2026-09-26*

## Context

The schema, JSON, time and ids that the server needs lived in the library a
site loads. The server therefore depended on the SDK's DSL and HTTP client,
which are for sites and change for their sake.

## Decision

- koya is three systems, one directory each under `src/`:
  - `koya-core` in `src/core/` holds the schema, validation, diff, JSON, name
    conversion, time and ULIDs.
  - `koya-sdk` in `src/sdk/` holds the schema DSL and the HTTP client.
  - `koya-server` in `src/server/` holds the server.
- `koya-sdk` and `koya-server` depend on `koya-core`, and not on each other.
  `spec/server/layers.lisp` fails if a file of the server uses `koya-sdk`.

## Consequences

- A site depends on `koya-sdk`, and never loads the server.
- A change made for sites' sake cannot reach the server except through
  `koya-core`.
