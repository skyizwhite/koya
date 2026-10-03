# A content id belongs to its space

*2026-10-04*

## Context

Content ids were unique across the whole server. A ULID never collides, but an
id given on create, as an import from another system keeps them, did: two sites
on one server, each moved from a CMS that numbered its posts `1`, `2`, …, could
not both keep their ids. The refusal also told one space's management key that
an id existed somewhere else, and an archive could not be imported where
another space already held one of its ids.

Every other way to a content already went through its space: the admin UI and
the delivery API name the space in the URL, references point within it, and a
space moves between servers with its keys and its webhook secret.

## Decision

A content is identified by its space and its id. `contents` is keyed by
`(space, id)`, and a content's history by the same pair. The same id may be
used once in each space.

## Consequences

- Imports from other systems keep their ids side by side, and an archive's ids
  collide only with contents of its own space, which an import refuses anyway.
- A conflict on create speaks of the space it was asked in, and of nothing else.
- Every lookup by id names the space; there is no server-wide lookup of a
  content by its id alone.
