# A content id is koya's to make

*2026-10-11*

## Context

Creating a content could give its id, any string of 1 to 64 letters, digits,
`-` or `_`, so that content arriving from another CMS kept the URLs made from
its ids. That left two ways to make an id and ids of every shape, for one use: a
site that keeps its old URLs can map them to the new ids, or keep them in a
slug, the field for a URL a person chooses.

## Decision

The server makes every content's id, as
[12 letters and digits](2026-10-10-a-content-id-koya-makes-is-twelve-letters-and-digits.md).
Creating a content that gives `id` is refused, not given another id in silence.

## Consequences

- An import from another CMS gets new ids; references between the imported
  contents are written with them.
- koya-sdk no longer exports `make-ulid`, which a site used to make an id to
  give.
- Ids given before stay as they are, and a space's archive keeps its ids when it
  is imported, so that its references hold.
