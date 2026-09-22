# Sessions live in the database

*2026-09-20*

## Context

The session store was in memory. Every restart and every redeploy logged the
owner out, which for a process that is redeployed whenever the schema changes is
most of the time.

## Decision

Sessions are rows in SQLite: 24 hours, extended on use, expired ones swept at
startup. An empty session is not stored, so a visitor who never logs in leaves
nothing behind.

## Consequences

A restart no longer ends a session. The cost is a write per request that touches
one, which at this size is nothing.
