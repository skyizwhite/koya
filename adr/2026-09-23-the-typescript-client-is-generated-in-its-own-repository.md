# The TypeScript client is generated from openapi.yaml, in its own repository

*2026-09-23*

## Context

`docs/openapi.yaml` and `docs/SCHEMA.md` were written so that clients in other
languages could exist, and TypeScript is the first one asked for (#4). Three
questions were open: whether it lives here or apart, whether it is written by
hand or generated, and whether a TypeScript project may own a schema — `plan`
and `deploy` had been the Lisp library's alone.

## Decision

- **Its own repository, `koya-ts-sdk`**, published to npm under that name. The
  Lisp build and the Node toolchain do not meet, and the client follows the API
  through the document rather than through shared code.
- **Generated from `openapi.yaml`**, with Orval's `fetch` client: the transport
  and the wire types are regenerated when the document changes, and only the
  typed layer over them — models, `include`, `fields`, the CLI — is written by
  hand. Orval was chosen over generators that drive the TypeScript compiler's
  JavaScript API, which TypeScript 7 no longer has.
- **A TypeScript project may own its schema.** The server computes the diff and
  refuses destructive changes without `force`, so a `deploy` from TypeScript is
  as safe as one from Lisp. The SDK's `koya plan` / `deploy` / `pull` / `types`
  are a CLI, run from npm scripts: on that side there is no REPL to keep them in.

For the document to generate well, it now names every operation (`operationId`),
names its request and response shapes, types each field `type` with its own
options, and says which properties are always present. The security scheme the
admin API uses is called `managementKey`, after the key it takes.

## Consequences

`openapi.yaml` is now an input to a build, not only a description: a change to
the API that it does not record reaches the TypeScript client as a wrong type.
The SDK copies the document with `npm run openapi:sync` and checks the
generated code in, so a change here is picked up there on purpose.

Two clients now implement the same calls. What they must agree on is the
document and SCHEMA.md, which stay in this repository.
