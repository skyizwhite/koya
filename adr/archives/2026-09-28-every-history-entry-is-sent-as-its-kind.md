# Every history entry is sent as its kind

Superseded by adr/2026-09-28-each-history-entry-is-sent-as-its-kind.md
Superseded by adr/2026-09-28-a-deleted-draft-is-sent-as-discard.md

*2026-09-28, restating a decision of the same day*

## Context

What was sent followed two rules at once. A publish or a draft save was sent as
what was done. An unpublish or a delete was sent only when the content had been
published, and a discard never was, because what is published did not change.
So a change to a draft could send `draft` or nothing, depending on how it was
made: a save sent `draft`; a discard, or a save back to the published data, sent
nothing. A receiver following the draft never heard of it going away.

## Decision

- Each entry a content's history keeps is sent, as its kind: `draft`,
  `publish`, `unpublish` or `discard`. A write that the history does not keep,
  because it changes nothing, sends nothing.
- Deleting a content sends `delete` whether or not it was published; the
  history goes with the content, so the delete is its own event.
- A `discard` carries the draft thrown away as `old` and the published data it
  falls back to as `new`. A `delete` of a content never published carries
  `null` for both.
- Creating is not its own event. It is kept as a `draft` or a `publish`, and
  sent as that.
- An import writes history and sends nothing, as
  `adr/2026-09-27-an-import-sends-no-webhooks.md` has it.

## Consequences

What a receiver hears matches what the history shows, one for one. A receiver
now also hears `discard`, and `delete` for a content that was never published.
