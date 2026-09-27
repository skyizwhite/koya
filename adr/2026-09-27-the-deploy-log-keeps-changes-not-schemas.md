# The deploy log keeps the changes, not the schema

*2026-09-27, restating a decision of 2026-09-23*

## Context

A deploy log could keep each schema that was deployed, or only what each deploy
changed.

## Decision

A deploy's row holds its changes. The schema document it deployed is not kept.

## Consequences

- The log answers what changed, not what the schema was. The schema itself is
  read from the space page or with `pull`.
- If the log should ever grow into rollback, that is when the document earns a
  column.
