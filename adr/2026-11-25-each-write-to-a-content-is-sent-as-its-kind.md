# Each write to a content is sent as its kind

*2026-11-25, restating a decision of 2026-09-28*

## Context

What was sent was each entry a content's history keeps. A model can now keep no
history (`adr/2026-11-25-a-model-keeps-a-history-only-when-it-asks-for-one.md`),
and a receiver following its contents still has to hear of every change.

## Decision

- Each write to a content is sent, as its kind: `draft`, `publish`,
  `unpublish` or `discard`. A draft save that changes nothing is no write and
  sends nothing (`adr/2026-09-25-a-draft-that-changes-nothing-is-none.md`).
- Whether the model keeps a history does not change what is sent.
- A `discard` carries the draft thrown away as `old` and the published data it
  falls back to as `new`.
- Creating is not its own event. It is sent as a `draft` or a `publish`.
- Deleting is sent as `adr/2026-09-28-a-deleted-draft-is-sent-as-discard.md`
  has it.
- An import writes contents and sends nothing, as
  `adr/2026-09-27-an-import-sends-no-webhooks.md` has it.

## Consequences

A receiver hears every change to a content, published or drafted, and for a
model that keeps a history what it hears matches what the history shows, one for
one.
