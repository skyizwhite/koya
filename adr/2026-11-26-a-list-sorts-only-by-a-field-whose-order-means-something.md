# A list sorts only by a field whose order means something

*2026-11-26*

## Context

A list's order is SQLite's order over the value a content keeps. For some
fields that value is not what a reader sorts by: a `media` or `reference` field
keeps an id, a `many` field an array, a `richtext` field its markup, and a
`select` field its option, which the schema puts in an order of its own. Sorting
by them gave an order that looked like a result but followed nothing a reader
could see. A `textarea` holds prose, which no one looks up by its first letters.

These fields could be made to sort: a reference by its label, a richtext by its
text, a select in the order of its options. Each needs its own read for an order
few would ask for.

## Decision

- A list sorts by a `text`, `slug`, `number`, `boolean`, `date` or `datetime`
  field, and by the system fields. No other field sorts.
- The rule is one, in `domain/query`, and holds for the content list, the
  delivery API and the admin API alike.
- The APIs refuse an order on any other field with `400 bad_query`, as they
  refuse an unknown field. The content list shows such a field's header without
  a sort, and a link asking for one falls back to the default order, as a stale
  link does.

## Consequences

A site that ordered by one of these fields gets `400` where it got an order
that meant nothing, and has to drop that order. Sorting a reference by its
label, or a select by its options, is a new decision when someone needs it.
