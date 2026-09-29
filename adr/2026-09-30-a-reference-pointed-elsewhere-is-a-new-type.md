# A reference pointed at another model is a new type

*2026-09-30*

## Context

A deploy compared a reference field's `model` as one of its options, and no
option change counted it, so pointing `tag` at `cat` deployed without `force`.
The stored ids went on naming `tag` contents, read as references to `cat`, and
the in-use check followed the new model, so a `tag` content others still named
could be deleted.

Two ways were weighed: count it as tightened options, which asks for `force`
and leaves the values, or as a change of type, which takes them.

## Decision

Changing the model a reference field points at is a change of the field's type:
it is destructive, and a forced deploy takes the field's values out of every
published object, draft and revision, as
`adr/2026-09-30-a-forced-field-change-takes-its-values-with-it.md` has it for a
type.

## Consequences

- No stored id names a content of a model the field no longer points at, so the
  in-use check and delivery never meet one.
- A value that fitted tightened options before can still be right after; an id
  of the old model never is, so nothing worth keeping is lost.
- Pointing the field back does not bring the values back.
