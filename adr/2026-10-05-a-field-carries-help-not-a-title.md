# A field carries help text, not a title

*2026-10-05*

## Context

The editor labels a field by its name (`coverImage`), and nothing in the schema
can tell the person editing what a field expects: an image's size, a length to
aim for, where the value shows on the site. Two options were proposed: a
`title` to label the field in place of its name, and a `help` text to describe
it.

## Decision

A field takes `help` alone: `(cover :media :help "1200x630")`, `"help":
"1200x630"` on the wire. Every type takes it, it must be a non-empty string,
and the editor shows it as plain text under the field's name.

There is no `title`. A field's name is already written for the person who reads
it, and it is read in English by an owner who understands it. What a name
cannot say is what the field expects, and that is what `help` says.

Like the model's label, it belongs to the schema rather than to the settings
page: only the site's repository knows what its fields expect.

## Consequences

Changing `help` is an ordinary, non-destructive options change in `plan`; no
stored content is checked against it. Should an editor who does not read the
names in English need a label, `title` can be added beside `help` as another
optional key without changing it.
