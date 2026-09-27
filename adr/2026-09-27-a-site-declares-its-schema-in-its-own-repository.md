# A site declares its schema in its own repository

*2026-09-27, restating a decision of 2026-09-20*

## Context

The schema could live in the CMS, edited through its admin UI, as most of them
do. But the site that consumes it is already a project under git, and the shape
of its content is part of how it is built.

## Decision

- A site declares its models in its own repository: with `defmodel` from
  `koya-sdk`, or with `defineSchema` from the TypeScript SDK.
- The declaration builds plain data, and the SDK sends it to the server as JSON.
- `plan` shows what would change, `deploy` applies it, and `pull` reads back
  what the server holds.
- The admin UI shows the schema but cannot edit it.

## Consequences

- The schema is reviewed and reverted like the rest of the site.
- A client in another language only has to send the same JSON.
