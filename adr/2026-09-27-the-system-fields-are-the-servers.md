# The system fields are the server's

*2026-09-27, restating a decision of 2026-09-20*

## Context

`id`, `createdAt`, `updatedAt`, `publishedAt` and `revisedAt` are the fields a
CMS is expected to keep honest, and the delivery API sorts and filters by them.

## Decision

The five are system fields. The server keeps them, as columns of `contents`
rather than inside the content's JSON, and a model may not declare a field by
any of their names.

## Consequences

The delivery API can sort and filter by them without looking inside the JSON.
A schema with a field named like one of them is refused.
