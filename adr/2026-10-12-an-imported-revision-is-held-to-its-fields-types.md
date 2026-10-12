# An imported revision is held to its fields' types

*2026-10-12*

## Context

An import checks a content's published data and draft as creating it would.
Its history cannot be held to the same: a deploy that tightens a field's
options — `required` turned on, `maxLength` lowered, a value dropped from
`options`, `many` switched — checks only the published data and drafts, and
leaves the revisions as they were. An archive exported from a koya that has
had such a deploy would then not import. Taking revisions unchecked lets an
archive put a value under a field that could never have held it, such as a
number under a rich text field.

## Decision

Each revision in an archive is checked against its model for what no deploy
leaves in a revision: a key that is not a field, a value not of its field's
type, a row of a custom field its repeater does not list. A field may hold one
value or several, whatever its `many` now says. The options a field has now are
not asked of it. The first revision that does not fit is named and nothing is
imported.

## Consequences

An archive koya exports imports again, except from a space whose history kept
rows of a custom field dropped from a repeater before a deploy took such rows
out of the revisions; the import names the first of them. A revision shown in the history or
restored holds only values its fields' types allow; restoring still checks a
value against the options and keeps the current one when it does not fit.
