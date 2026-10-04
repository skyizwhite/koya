# Rich text is matched as the text it reads, kept beside it when written

*2026-10-04*

## Context

Rich text is stored as HTML. Matching it as stored made `strong` or `class`
match nearly every content, missed a phrase broken by an inline tag, and missed
`AT&T` stored as `AT&amp;T`.

Making the text when a query asks, by an SQL function, cost about 0.22 ms per
row for 5 KB of rich text, 35 times a plain `LIKE`: 220 ms to search 1,000
contents, twice that for a list, which counts as well as reads a page. A
content's text changes only when its data is written, so it can be made then.

## Decision

- `contains`, `not_contains` and `begins_with` on a `richtext` field, and so the
  search, match its text: the tags taken out, a block element read as a space
  and an inline one as nothing, character references read as their characters
  (except those that name no character text can hold), and runs of space made
  one.
- `contents` keeps that text in `published_text` and `draft_text`, a JSON object
  of each string value of the data by field. It is written with the data, by the
  store, from one domain function, and is null exactly when its data is. Data
  with no string has `{}`.
- Every string value is kept, whatever its field's type: the store is handed a
  content without its model. Only rich text filters read it.
- An export leaves the text out, and an import makes it again.
- Rejected: triggers or generated columns calling an SQL function, which hide
  the work and fail on any connection that does not register the function; and
  FTS5, which matches words rather than any part of the text, and needs a
  trigram tokenizer for Japanese.

## Consequences

- A search reads stored text with a plain `LIKE`: about 6 ms for 1,000 contents.
- Every write turns its data's strings into text, and the text takes room
  beside the data.
- A migration that rebuilds `contents` copies the two columns; one that changes
  how text is made fills them again.
- `equals`, `exists` and ordering still see the HTML.
