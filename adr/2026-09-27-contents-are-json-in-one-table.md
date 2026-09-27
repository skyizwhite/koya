# Contents are JSON documents in one table

*2026-09-27, restating a decision of 2026-09-20*

## Context

If content were stored relationally, every model a site declares would be a
table, and every schema change would be a migration: written, reviewed and
deployed by the person who only wanted to add a field.

## Decision

- One `contents` table holds every content of every model of every space.
- A content's `published` and `draft` are JSON documents, and a model's fields
  are keys inside them.

## Consequences

- Deploying a schema never changes a table.
- Removing a field does not delete what it held. The key simply stops being
  read.
- Queries over fields are `json_extract` in the WHERE and the ORDER BY, which
  SQLite does well enough at this size and which the delivery API's filters
  already need.
