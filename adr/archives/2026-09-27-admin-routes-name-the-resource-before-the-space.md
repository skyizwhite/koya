# Admin API routes name the resource before the space

Superseded by adr/2026-10-05-api-routes-put-the-space-first.md

*2026-09-27, restating a decision of 2026-09-20*

## Context

Every admin API route addresses one space. If the space came first, as in
`/admin/api/<space>/<resource>`, a space named after a resource, such as
`schema`, would collide with it.

## Decision

Admin API routes are `/admin/api/<resource>/<space>/…`, as in
`/admin/api/schema/<space>` and `/admin/api/contents/<space>/<model>`.

## Consequences

Any name a space can have is safe; no space name is reserved.
