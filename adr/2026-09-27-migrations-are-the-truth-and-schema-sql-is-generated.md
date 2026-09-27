# Migrations are the truth, and schema.sql is generated from them

*2026-09-27, restating a decision of 2026-09-22*

## Context

Reading the current shape of the database meant reading every migration and
applying them in one's head. The declarative alternative was considered: write
the shape you want, and let a tool diff it. SQLite's `ALTER TABLE` is thin, so
such a tool would change a table by copying it.

## Decision

- Migrations are the source of truth. They are forward-only and apply
  themselves at startup.
- `src/server/infra/db/schema.sql` is a generated snapshot of a fully migrated
  database, written by `(koya-server:write-schema-snapshot)`.
- A spec fails while the snapshot is stale.

## Consequences

The current shape is one file to read, and nothing computes DDL at deploy time.
The cost is remembering to regenerate the snapshot, and the spec does that
remembering.
