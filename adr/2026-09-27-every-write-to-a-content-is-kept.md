# Every write to a content is kept

*2026-09-27, restating a decision of 2026-09-23*

## Context

A content row holds its published data and its draft, nothing else. Without
more, saving a draft overwrites the one before it and publishing overwrites what
was live, so a paragraph deleted by mistake is gone, and nobody can say what an
entry looked like last month.

## Decision

- Every write to a content leaves a row in `content_revisions`, in the same
  transaction as the write: the data it left the content with, the event
  (`draft`, `publish`, `unpublish` or `discard`), who made it (`owner` or
  `key:<label>`) and when.
- A draft save that changes nothing is not a write, and leaves no revision.
- Revisions are kept for as long as their content exists, with no cap. A deleted
  content takes its revisions with it (`ON DELETE CASCADE`), since there is
  nothing left to restore into.
- A field renamed with `:was` is renamed in the revisions as well, since it is
  the same field.
- Revision ids are an integer sequence rather than ULIDs, so two writes in the
  same millisecond still come out in the order they happened.

## Consequences

The table grows with every save, one full copy of the data each time. For the
contents of a small site in SQLite that is small; if it stops being, a cap can
be added.
