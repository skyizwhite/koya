# The TypeScript client has its own repository

*2026-09-27, restating a decision of 2026-09-23*

## Context

Sites that use koya are written in TypeScript, so they need a TypeScript
client. It could live in this repository beside the server and the Lisp SDK, or
apart.

## Decision

The TypeScript client is `koya-ts-sdk`, in a repository of its own. It follows
the API through `docs/openapi.yaml` and `docs/SCHEMA.md`, not through code
shared with this repository.

## Consequences

The Lisp build and the Node toolchain do not meet.

Two clients implement the same calls. What they must agree on is the document
and SCHEMA.md, which stay in this repository. The client copies the document
with `npm run openapi:sync`, so a change here is picked up there on purpose.
