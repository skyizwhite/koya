# A new content may bring its own dates

*2026-10-11, restating a decision of 2026-09-27*

## Context

Content arriving from another CMS already has dates, and a site may show them
or order by them. Taking now instead dates every imported content the day of
the import.

## Decision

Creating a content may give its `createdAt`, `updatedAt`, `publishedAt` and
`revisedAt`. Without them the server uses now.

## Consequences

Content can be brought in with its dates intact. After it is created, only the
server writes them.
