# A model keeps a history only when it asks for one

*2026-11-25*

## Context

Every write to every content was kept as a revision, one full copy of its data
each time. Many models have a past nobody reads: a settings object saved now and
then, a list a script rewrites every hour. They paid for a history like the
models whose editors need one, and the table grew with each of them.

## Decision

- A model keeps a history only when its definition says so: `"history": true`
  in the schema, `:history t` in `defmodel`. Without it a write to its contents
  leaves no revision, and the admin UI has no history for them: no link in the
  editor, and the history page answers `404`.
- A deploy that takes `history` away from a model deletes that model's
  revisions, and is destructive: the deploy is refused until it is forced, as
  removing a field is. Giving a model `history` is not destructive, and its
  history starts with the next write.
- Every model a space had before this decision was given `history: true` when
  the server was upgraded, since its history had been kept until then.
- An import keeps the revisions of a model only when the archive's schema gives
  it `history`.

Hiding the revisions of a model that no longer keeps a history, instead of
deleting them, was weighed. It leaves rows nothing reads, and turning `history`
back on would bring back a past with a gap in it as if it were whole.

## Consequences

A site asks for a history where its editors need one, and other models cost
nothing for it. Upgrading changes nothing by itself; the first deploy of a
schema that leaves `history` out of a model asks before its history goes. What a
write sends to webhooks does not depend on it
(`adr/2026-11-25-each-write-to-a-content-is-sent-as-its-kind.md`).
