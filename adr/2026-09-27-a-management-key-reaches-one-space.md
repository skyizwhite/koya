# A management key reaches one space

*2026-09-27, restating a decision of 2026-09-22*

## Context

A management key can deploy a schema and write every content. A key that
reached every space would let the `.env` of one site drive every other site on
the instance.

## Decision

A management key belongs to one space. Every admin API route but
`/admin/api/me` has the space as its second path segment, and the guard on
`/admin/api` refuses a key sent to any other space. The check is on the path,
deny by default, so a route added later is covered without being remembered.

## Consequences

A site's environment cannot reach another site.
