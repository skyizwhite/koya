# A key reaches one space, and the two kinds stay apart

*2026-09-22*

## Context

Management keys were instance-wide, so the `.env` of one site could drive every
other site on the instance. Delivery keys were already per-space.

## Decision

A management key belongs to one space. Every admin route but `/admin/api/me` has
the space as its second path segment, and the middleware refuses a key sent
anywhere else — deny by default, so a route added later is covered without being
remembered.

Delivery keys and management keys keep separate tables. Merging them behind a
`scope` column was considered and refused: that the columns are the same is a
coincidence, and it would move the guarantee that a delivery key cannot deploy a
schema into one `WHERE` clause that someone can forget.

## Consequences

A site's environment cannot reach another site. The existing instance-wide keys
could not be assigned to a space, so migration 6 dropped them and they were
issued again.
