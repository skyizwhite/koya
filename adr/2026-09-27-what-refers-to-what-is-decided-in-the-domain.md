# What refers to what is decided in the domain, and the store only narrows the search

*2026-09-27, restating a decision of 2026-09-25*

## Context

Two things can refuse to be taken away: a content that another one refers to,
and a media that a content uses. Only part of finding them is a way of storing.
A `LIKE` on the stored JSON narrows the rows. The rest is koya's rules:

- a text field that happens to hold an id is not a reference
- a richtext field uses a media by its URL
- a field that a deploy removed is no longer read

## Decision

- `domain/references` holds the rules. `reference-fields` and `media-fields` say
  which fields of a schema can point at a content of a model or at a media.
  `refers-p` and `mentioned-ids` say whether a content's published or draft data
  does.
- The store only narrows the search. The port `contents-mentioning` returns the
  contents whose JSON holds a string anywhere, which is every content that can
  refer to it and possibly some that do not.
- The use cases count, by applying the domain's rules to what the store
  returned: `content-references` in `usecases/contents`, and `media-references`
  and `media-reference-counts` in `usecases/media`.

## Consequences

- The rules can be specified without a database, in
  `spec/server/domain/references.lisp`.
- A page of the media library still counts all its cards in one pass over the
  space's contents.
