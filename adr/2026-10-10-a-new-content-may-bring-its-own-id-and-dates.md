# A new content may bring its own id and dates

*2026-10-10, restating a decision of 2026-09-27*

## Context

Content arriving from another CMS already has an id and dates, and its URLs are
made from the id. Rewriting them on the way in rewrites every URL.

## Decision

Creating a content may give its `id`, `createdAt`, `updatedAt`, `publishedAt`
and `revisedAt`. The id may be any string of 1 to 64 letters, digits, `-` or
`_`, and one its space already holds is refused. Without them the server makes
[an id of its own](2026-10-10-a-content-id-koya-makes-is-twelve-letters-and-digits.md)
and uses now.

## Consequences

Content can be brought in with its dates and its URLs intact. After it is
created, only the server writes them.
