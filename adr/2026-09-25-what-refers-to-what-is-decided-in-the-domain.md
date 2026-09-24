# What refers to what is decided in the domain, and the store only narrows the search

*2026-09-25*

## Context

Two things can refuse to be taken away:

- a content that another one refers to
- a media that a content uses

`adr/2026-09-25-the-server-is-layered-and-depends-inward.md` left the counting
of both in `infra/db`, on the grounds that SQL keeps it cheap. But only part of
it was SQL. A `LIKE` on the stored JSON narrowed the rows. Everything after that
was Lisp: which fields count, and whether a value holds the id. That part is a
rule of koya's, not a way of storing:

- a text field that happens to hold an id is not a reference
- a richtext field uses a media by its URL
- a field a deploy removed is no longer read

## Decision

- `domain/references` holds the rules. `reference-fields` and `media-fields`
  say which fields of a schema can point at a content of a model or at a media.
  `refers-p` and `mentioned-ids` say whether a content's published or draft data
  does.
- The store narrows the search and nothing more. The port
  `contents-mentioning` returns the contents whose JSON holds a string
  anywhere. That is every content that can refer to it, and possibly some that
  do not.
- The use cases count: `content-references` in
  `usecases/contents/references`, and `media-references` and
  `media-reference-counts` in `usecases/media/library`. Each loads the schema
  and applies the domain's rules to what the store returned. A page of the
  library still counts all its cards in one pass over the space's contents.

## Consequences

- The store reads the same rows as before, and each is parsed once, as before.
- The rules can be tested without a database (`tests/server/domain/references.lisp`).
- The ports lose `content-references`, `media-references` and
  `media-reference-counts`; `contents-mentioning` takes their place.
