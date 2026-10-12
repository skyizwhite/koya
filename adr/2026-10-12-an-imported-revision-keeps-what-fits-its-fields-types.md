# An imported revision keeps what fits its fields' types

*2026-10-12*

## Context

An import checks a content's published data and draft as creating it would.
Its history cannot be held to the same: a deploy that tightens a field's
options — `required` turned on, `maxLength` lowered, a value dropped from
`options`, `many` switched — checks only the published data and drafts, and
leaves the revisions as they were. Older databases also hold revisions that no
deploy cleaned: values of a field retyped before a retyped field took its
values with it, and rows of a custom field taken out of a repeater. Taking
revisions unchecked lets an archive put a value under a field that could never
have held it, such as a number under a rich text field; refusing them would
leave some archives koya exported unable to import.

## Decision

Each revision in an archive is fitted to its model's fields' types before it is
stored: a key that is not a field, a value not of its field's type, several
values under a field that cannot hold several, and a row of a custom field its
repeater does not list are left out. A field that can hold several may hold one
or several, whatever its `many` now says. The options a field has now are not
asked of a revision. Nothing in a revision makes an import fail.

## Consequences

Every archive koya exports imports again, and the history it brings holds only
values its fields' types allow. A version that loses a value on import shows
without it in the history; restoring still checks each value against the
options and keeps the current one when it does not fit.
