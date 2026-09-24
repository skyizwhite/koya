# A referenced content cannot be taken away, and only the schema's fields refer

*2026-09-24*

## Context

A media that some content uses could not be deleted, but a content that
another content refers to could be deleted or unpublished at will. The
reference was left pointing at nothing: the delivery API went on returning the
id when it was not included, and a site that followed it got a 404.

Both checks also have to decide what counts as a use. The media check searched
the stored JSON as text. A deploy that removes a field leaves that field's
values in the stored JSON, so a media referred to only by a removed field was
held by something no one could see or edit, and could never be deleted.

## Decision

A content that another content refers to, in its published data or its draft,
cannot be deleted, nor unpublished while it is published: `409 in_use`, from the
admin API, the editor and the list's bulk actions alike. Unpublishing a draft is
not refused, since it takes nothing away. The user takes the reference out
first. There is no "delete anyway".

For media and contents alike, only the fields in the current schema count: a
`media` or `richtext` field for a media, a `reference` field pointing at the
content's model for a content. Values left in a field a deploy removed hold
nothing. A text field that happens to contain an id is not a use.

## Consequences

Deleting a model's contents in bulk can refuse some of them because others in
the same selection refer to them. Doing it again after the referring ones are
gone completes it.

A deleted model takes its contents with it without asking (a deploy says it is
destructive). If a removed field is added back, the ids it kept count again,
and any that point at something deleted in the meantime come out as missing,
as a reference to a deleted content always has.
