# SQL text holds only what koya wrote

*2026-11-21*

## Context

The stores write SQL as text, and some queries are put together from parts: a
condition that is there or not, a list of ids, and above all a delivery query's
filters, which reach into a content's JSON by field name. Field names went into
the text as JSON paths (`'$.title'`). That was safe only because a schema
refuses a field name that is not a camelCase identifier, a check made far from
the SQL it protects. Each store also put its optional conditions together in a
way of its own.

Three libraries were tried against koya's queries. sxql's query composer wrote
`RETURNING` before `ON CONFLICT` and took a subquery given to `set=` for a
string. lisql takes no value at run time and breaks parentheses and
subqueries. cl-yesql keeps fixed queries well, but a delivery query's filters
cannot be a fixed query, and it brings some forty systems with it.

## Decision

- SQL stays text, written in the store that runs it.
- Where a query is put together, its parts are made with `infra/db/sql`: each
  part is its text and its values, and joining parts keeps the values in the
  order of the text.
- The text holds only what koya wrote. Every value is bound, and so is a
  field's JSON path: a field name never goes into the text.

## Consequences

- Whether a query is safe no longer rests on the schema's field name check.
- Optional conditions, id lists and LIKE patterns are made one way in every
  store.
- SQLite's own syntax (`json_each`, `ON CONFLICT … RETURNING`, `LIKE …
  ESCAPE`) is written as it is, with no library between koya and SQLite.
