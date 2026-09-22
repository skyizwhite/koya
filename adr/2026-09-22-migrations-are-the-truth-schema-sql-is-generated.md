# Migrations are the truth; schema.sql is generated from them

*2026-09-22*

## Context

Reading the current shape of the database meant reading eight migrations and
applying them in one's head. The declarative alternative — write the shape you
want, let a tool diff it — was considered.

## Decision

Migrations stay the source of truth, forward-only, applied at startup.
`src/server/db/schema.sql` is a generated snapshot of a fully migrated database,
written by `(koya-server:write-schema-snapshot)`, and a test fails when it is
stale.

## Consequences

The current shape is one file to read, without a tool computing DDL at deploy
time — which SQLite, whose `ALTER TABLE` is thin, would do by copying tables.
The cost is remembering to regenerate, which the test does the remembering for.
