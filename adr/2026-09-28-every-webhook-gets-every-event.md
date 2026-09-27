# Every webhook is sent every event

*2026-09-28, restating a decision of 2026-09-22*

## Context

A webhook could list the events it wants. Then a hook wanting everything has to
say so, and the list is one more thing to read in the schema.

## Decision

- There is nothing to subscribe to. Every webhook is sent every event; which
  events there are is `adr/2026-09-28-a-webhook-is-sent-for-every-history-entry.md`.
- The payload's `event` says which, and the receiver decides what to act on.

## Consequences

A receiver must look at `event`, which a revalidation hook wants to do anyway to
ignore changes to a draft.
