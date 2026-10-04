# The delivery API searches with q, as the content list does

*2026-10-04*

## Context

A site's search box needed an outside search service: the delivery API could
only filter one field at a time with `contains`. The admin UI's content list
already searches every text field through the same query.

## Decision

- A list takes `q`. A content matches when the text of one of its model's
  `text`, `textarea`, `slug` or `richtext` fields contains it, or when it is the
  content's whole id: the content list's search, and the same code.
- `q` is one phrase, matched as typed: it is not split into words.
- With `filters`, both apply. The admin API's list takes `q` too.
- It is SQL `LIKE` over the stored JSON, without an index.

## Consequences

- A site can offer a search box with a delivery key alone.
- Case is ignored for ASCII letters only, as `LIKE` does, and every search reads
  every content of the model. That is enough at a single owner's size; a
  full-text index (FTS5) waits until a search is slow.
