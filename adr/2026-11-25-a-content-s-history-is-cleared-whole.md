# A content's history is cleared whole

*2026-11-25*

## Context

A model that keeps a history keeps every write to its contents for as long as
they exist (`adr/2026-11-25-a-kept-history-holds-every-write.md`). An editor can
want a content's past gone while the content stays: versions that hold what
should not have been written, or a long history nobody will read again.

## Decision

- The history page of a content has **Clear history**, which deletes every
  revision of that content, after asking first. The content, its published data
  and its draft are left as they are, and the next write starts its history
  again.
- It is the whole history of one content. Removing single revisions was weighed
  and left out: each entry is shown against the one before it, and a gap would
  show a change nobody made. A model's whole history goes with taking `history`
  away from it in a deploy
  (`adr/2026-11-25-a-model-keeps-a-history-only-when-it-asks-for-one.md`).
- It is done in the admin UI only, as the history is read there only
  (`adr/2026-09-27-the-history-is-read-in-the-admin-ui-only.md`), and sends no
  webhook, since no content changes.

## Consequences

Clearing cannot be undone, and an old version cleared cannot be restored.
