# A content id belongs to its space

*2026-10-11, restating a decision of 2026-10-04*

## Context

A space moves between servers as an archive, with its contents' ids, and the
ids it holds include ones given on create before
[koya made every id](2026-10-11-a-content-id-is-koya-s-to-make.md): two sites
on one server, each moved from a CMS that numbered its posts `1`, `2`, …, may
hold the same ids. Were ids unique across the server, such an archive could not
be imported where another space held one of its ids, and the refusal would
tell one space's management key that an id existed somewhere else.

Every other way to a content already goes through its space: the admin UI and
the delivery API name the space in the URL, references point within it, and a
space moves between servers with its keys and its webhook secret.

## Decision

A content is identified by its space and its id. `contents` is keyed by
`(space, id)`, and a content's history by the same pair. The same id may be
used once in each space.

## Consequences

- An archive's ids collide only with contents of its own space, which an import
  refuses anyway.
- An id koya draws for a new content is checked against its space only.
- Every lookup by id names the space; there is no server-wide lookup of a
  content by its id alone.
