# A slug is typed, not generated

*2026-10-10*

## Context

A `slug` field had to name a `text` or `textarea` field in `from`, and a blank
slug was filled from it on save: lowercased, every run of other characters made
one hyphen. That works for a title in English. A title in Japanese has no
letters it keeps, so the slug stayed blank; a title that mixes them, such as
`Lisp入門`, became `lisp`, a slug nobody chose that passed `required` without
a word. And `from` was required, so a site whose titles are not in English had
to point it at a field it did not want a slug made from.

Romanising the title instead was weighed: a kanji has more than one reading,
so the slug it made would still need checking by hand.

## Decision

A slug is what the editor types. The `slug` field has no `from` option, and
nothing fills a blank slug. A schema that gives `from` is refused as one that
gives any option its type does not take.

## Consequences

- A slug that must be there is a `required` slug; the editor asks for it like
  any required field.
- Schemas stored before this lose `from` when the server is upgraded, and an
  archive exported before this is imported without it. A schema deployed from a
  site's code that still gives it is refused until it is taken out.
