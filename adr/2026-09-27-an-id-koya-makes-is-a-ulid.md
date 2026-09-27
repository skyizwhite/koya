# An id koya makes is a ULID

*2026-09-27, restating a decision of 2026-09-20*

## Context

Contents, media, keys and deploys need ids, made by koya itself.

## Decision

Every id koya makes is a ULID, from `koya-core/ulid`.

## Consequences

- An id is made without asking the database, and ids sort in the order they
  were made.
- A content may still be given its own id by whoever creates it, as
  `adr/2026-09-27-a-new-content-may-bring-its-id-and-dates.md` allows. Only the ids
  koya makes are ULIDs.
