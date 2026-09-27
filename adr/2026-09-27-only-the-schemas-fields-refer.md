# Only the current schema's fields count as a use

*2026-09-27, restating a decision of 2026-09-24*

## Context

A media that a content uses and a content that another refers to both refuse to
be taken away, so something has to decide what counts as a use. Searching the
stored JSON as text finds too much. A deploy that removes a field leaves that
field's values in the stored JSON, so a media referred to only by a removed
field would be held by something no one can see or edit, and could never be
deleted.

## Decision

- Only the fields in the current schema count: a `media` or `richtext` field
  for a media, a `reference` field pointing at the content's model for a
  content.
- Values left in a field a deploy removed hold nothing.
- A text field that happens to contain an id is not a use.

## Consequences

If a removed field is added back, the ids it kept count again, and any that
point at something deleted in the meantime come out as missing, as a reference
to a deleted content always has.
