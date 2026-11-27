# There is nothing to subscribe to

*2026-09-28, restating a decision of 2026-09-22*

## Context

A webhook could list the events it wants. Then a hook wanting everything has to
say so, and the list is one more thing to read in the schema.

## Decision

- There is nothing to subscribe to. Every webhook is sent every event; which
  events there are is `adr/2026-09-28-each-history-entry-is-sent-as-its-kind.md`
  and `adr/2026-09-28-a-deleted-draft-is-sent-as-discard.md`.
- The payload's `event` says which.

## Consequences

A receiver that acts on some events only tells them apart by `event`.
