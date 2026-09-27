# A media field refers to a file in the space's library

*2026-09-27, restating a decision of 2026-09-20*

## Context

A picture could belong to the content that uses it, uploaded with it and gone
with it, or to a library that contents pick from.

## Decision

- Media belongs to a space's library. A `:media` field holds the id of a file in
  it, not a file of its own.
- The library is reached from its own page and from a picker in the editor, and
  both draw it with the same components.

## Consequences

- The same picture can be used by several contents.
- A file that some content still uses cannot be deleted.
