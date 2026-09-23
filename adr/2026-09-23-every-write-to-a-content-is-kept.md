# Every write to a content is kept, and a restore goes through the editor

*2026-09-23*

## Context

A content row holds its published data and its draft, nothing else. Saving a
draft overwrote the one before it and publishing overwrote what was live, so a
paragraph deleted by mistake was gone, and nobody could say what an entry
looked like last month.

## Decision

Every write to a content leaves a row in `content_revisions`, in the same
transaction as the write: the data it left the content with, the event
(`draft`, `publish`, `unpublish`, `discard`), who made it (`owner` or
`key:<label>`, as for deploys) and when. A draft save that changes nothing
against the newest revision is not an event. Revisions are kept for as long as
their content exists; there is no cap.

The history is read in two ways at `/s/{space}/m/{model}/{id}/history`: the
published versions only, each compared with the one published before it, or
every revision, each compared with the one before it. It is admin UI only — the
delivery API and the admin API do not read it.

A restore does not write. It opens the editor with the revision's data in the
form, and nothing is stored until the draft is saved or published — so a
restore can never replace what is live by itself, and what it could not bring
back is read before anything happens. Field by field, against the schema and
the space as they are now:

- a field that no longer exists is left out;
- a value the field no longer accepts (its type or its options changed, it
  became required, a unique value is taken) keeps what the editor has now;
- a reference to a content that has been deleted, unpublished or never
  published is dropped, and a media id that is no longer in the library too — a
  re-uploaded file is a new id, so it is the same case.

The editor lists each of these above the form. A deleted content takes its
revisions with it (`ON DELETE CASCADE`): there is nothing left to restore into.

A field renamed with `:was` is renamed in the revisions as well, since it is the
same field.

## Consequences

The table grows with every save, one full copy of the data each time. For the
contents of a small site in SQLite that is small; if it stops being, a cap is a
setting on the settings page and a `DELETE` after each insert, the way the
deploy log keeps its last 100.

Revision ids are an integer sequence rather than ULIDs: two writes in the same
millisecond still come out in the order they happened, and the migration can
write the first revision of every existing content in SQL.
