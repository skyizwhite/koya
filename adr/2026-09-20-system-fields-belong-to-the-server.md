# The system fields are the server's, except when importing

*2026-09-20*

## Context

`createdAt`, `updatedAt`, `publishedAt`, `revisedAt` and `id` are the fields a
CMS is expected to keep honest. But content arriving from somewhere else already
has all five, and a migration that rewrites them rewrites every URL with them.

## Decision

The five are system fields: the server manages them, and a model may not declare
a field by those names.

Creating a content may nonetheless give any of them explicitly, including the
id, which may be any URL-safe string rather than a ULID. Without them the server
uses now, and a ULID.

## Consequences

Content can be brought in with its dates and its URLs intact, and afterwards
nothing but the server writes them. The delivery API can sort and filter by them
without looking inside the JSON, since they are real columns.
