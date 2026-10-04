# Rich text is matched as the text it reads

*2026-10-04*

## Context

Rich text is stored as HTML. Matching it as stored made `strong` or `class`
match nearly every content, missed a phrase broken by an inline tag, and missed
`AT&T` stored as `AT&amp;T`. A plain-text copy kept beside each field would need
a migration, a backfill and a second write on every save of a draft or a
publish.

## Decision

- `contains`, `not_contains` and `begins_with` on a `richtext` field, and so the
  search, match its text: the tags taken out, a block element read as a space
  and an inline one as nothing, character references read as their characters,
  and runs of space made one.
- The text is made when a query asks, by an SQL function koya registers on its
  connection, `koya_text`. Nothing about it is stored.

## Consequences

- No schema change and nothing to keep in step: a search sees rich text as it
  is stored now.
- Each search turns every rich text it reads into text, in Lisp, row by row.
- `equals`, `exists` and ordering still see the HTML.
