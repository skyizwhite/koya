# A content's status says which versions it has

*2026-10-12*

## Context

A content has a published version, a draft, or both. Each was a hash table,
and a version that was not there was `nil`. Since
[a content's data is a plist](2026-10-12-content-data-is-a-plist.md), data
with no values is `nil` too: a content of a model whose fields are all optional,
published with nothing filled in, would read as not published.

## Decision

- The `content` struct holds its status, `draft`, `published` or
  `published+draft`, as the `contents` table does, and each write sets it by
  the transitions in `domain/content`.
- Whether a content has a version is asked with `content-published-p` and
  `content-draft-p`. Its `published` and `draft` hold that version's data and
  are read only when it is there.
- A store writes a version's column only when the status has it, as `{}` when
  its data is empty, and reads the status from its column.
- Publishing takes the data it is given, empty included; only when no data is
  given does it take the draft.

## Consequences

- A version with no values is a version: it is published, delivered and
  exported as one.
- What has a version and what the version holds are two questions, and code
  that asks one does not answer the other.
