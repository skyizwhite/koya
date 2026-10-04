# API routes put the space first

*2026-10-05*

## Context

A space holds models, and a model its contents, so a path that follows that
order reads from the outside in. The delivery API was `/api/v1/{space}/…`, while
the admin API put the resource first, `/admin/api/{resource}/{space}/…`, so that
a space named after a resource could not collide with it. A space name collides
only with a route that names no space and has the same shape as a space's
route; the admin API has one such route, `/admin/api/me`, and no route of a
space is a single segment.

## Decision

Both APIs name the space first: `/api/v1/{space}/…` and `/admin/api/{space}/…`,
as in `/admin/api/{space}/schema`, `/admin/api/{space}/keys` and
`/admin/api/{space}/media`. A route that names no space is a single segment, as
`/admin/api/me` is.

## Consequences

- The two APIs and the admin UI (`/s/{space}/…`) share one order.
- Any name a space can have is still safe, `me` included: its routes have more
  than one segment.
- A route added later that names no space keeps to one segment, or a space name
  could collide with it.
