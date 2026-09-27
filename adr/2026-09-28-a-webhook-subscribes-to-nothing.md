# A webhook subscribes to nothing

*2026-09-28, restating a decision of 2026-09-22*

## Context

A webhook could list the events it wants. Then a hook wanting everything has to
say so, and the list is one more thing to read in the schema.

## Decision

- There is nothing to subscribe to. Every webhook is sent every event; which
  events there are is `adr/2026-09-28-every-history-entry-is-sent-as-its-kind.md`.
- The payload's `event` says which.

## Consequences

A receiver that acts on some events only tells them apart by `event`.
