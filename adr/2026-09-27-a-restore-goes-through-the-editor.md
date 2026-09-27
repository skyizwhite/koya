# A restore goes through the editor

*2026-09-27, restating a decision of 2026-09-23*

## Context

An old revision was written against the schema and the space as they were then.
Fields have since been removed or changed, and what it refers to may be gone.

## Decision

A restore does not write. It opens the editor with the revision's data in the
form, and nothing is stored until the draft is saved or published. What it
could not bring back is decided field by field, against the schema and the
space as they are now:

- a field that no longer exists is left out;
- a value the field no longer accepts (its type or its options changed, it
  became required, a unique value is taken) keeps what the editor has now;
- a reference to a content that has been deleted or is not published is
  dropped, and so is a media id that is no longer in the library. A re-uploaded
  file is a new id, so it is the same case.

The editor lists each of these above the form.

## Consequences

A restore can never replace what is live by itself, and what it could not bring
back is read before anything is stored.
