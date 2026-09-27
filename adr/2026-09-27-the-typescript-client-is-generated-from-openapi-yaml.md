# The TypeScript client is generated from openapi.yaml

*2026-09-27, restating a decision of 2026-09-23*

## Context

A client written by hand has to be kept in step with the API call by call.

## Decision

- The transport and the wire types of `koya-ts-sdk` are generated from
  `docs/openapi.yaml` with Orval's `fetch` client, and the generated code is
  checked in.
- Only the typed layer over them is written by hand: the models, `include`,
  `fields` and the CLI.
- Orval was chosen over generators that drive the TypeScript compiler's
  JavaScript API, which TypeScript 7 no longer has.

## Consequences

`openapi.yaml` is an input to a build, not only a description. It names every
operation (`operationId`) and its request and response shapes, types each
field `type` with its own options, and says which properties are always
present. A change to the API that it does not record reaches the TypeScript
client as a wrong type.
