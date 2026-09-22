# SQLite, and contents as JSON in one table

*2026-09-20*

## Context

A CMS for one owner and a handful of sites. Every model a site declares would be
a table if content were stored relationally, so every schema change would be a
migration — written, reviewed and deployed by the person who only wanted to add
a field.

## Decision

SQLite, with no abstraction layer over it. One `contents` table for every model
of every space; `published` and `draft` are JSON documents, and a model's fields
are keys inside them. Ids are ULIDs. Migrations are forward-only and apply
themselves at startup.

## Consequences

Deploying a schema never changes a table, and removing a field does not delete
what it held — the key simply stops being read. Queries over fields are
`json_extract` in the WHERE and the ORDER BY, which SQLite does well enough at
this size and which the delivery API's filters already need.

There is no second database to support, so nothing is written twice. Down
migrations do not exist: one process, one file, restore from the volume backup.
