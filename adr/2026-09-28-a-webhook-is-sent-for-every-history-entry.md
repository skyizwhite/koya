# A webhook is sent for every history entry

*2026-09-28*

## Context

What was sent followed two rules at once. A publish or a draft save was sent as
what was done. An unpublish or a delete was sent only when the content had been
published, and a discard never was, because what is published did not change.
So a change to a draft could send `draft` or nothing, depending on how it was
made: a save sent `draft`; a discard, or a save back to the published data, sent
nothing. A preview that follows the draft never heard of the draft going away.

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

## Consequences

What a receiver hears matches what the history shows, one for one. A receiver
that revalidates a site ignores `draft` and `discard`; one that ignored only
`draft` now revalidates on a discard and on deleting a draft, which does nothing
worse than revalidate.
