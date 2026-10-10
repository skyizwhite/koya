# A new content may bring its own id and dates

Superseded by adr/2026-10-10-a-new-content-may-bring-its-own-id-and-dates.md

*2026-09-27, restating a decision of 2026-09-20*

## Context

Content arriving from another CMS already has an id and dates, and its URLs are
made from the id. Rewriting them on the way in rewrites every URL.

## Decision

Creating a content may give its `id`, `createdAt`, `updatedAt`, `publishedAt`
and `revisedAt`. The id may be any string of 1 to 64 letters, digits, `-` or
`_`, not only a ULID, and one already taken is refused. Without them the server
uses a ULID and now.

## Consequences

Content can be brought in with its dates and its URLs intact. After it is
created, only the server writes them.
