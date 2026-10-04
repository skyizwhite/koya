# A list of one kind is `many` on its field

*2026-10-05*

## Context

A gallery is several images in one field. A repeater
(`adr/2026-10-05-a-repeater-holds-rows-of-custom-fields.md`) can hold them, but
each image then becomes a row with a `fieldId` it does not need. A `collection`
type wrapping one built-in field was proposed for lists of one kind. `select`
and `reference` already take `many`, whose value is an array of their values.

## Decision

A list of one kind is `many` on the field, starting with `media`:
`{"name": "photos", "type": "media", "many": true}`, an array of media ids in
the order given. A `collection` type would hold the same array, and beside
`many` it would be a second way to write it; moving `select` and `reference`
over would break every schema that uses them.

The field's options apply to each value, as they do for `select` and
`reference`, and a type that later needs a list takes `many` the same way.

## Consequences

The editor draws each `many` type its own way: options as checkboxes,
references as chips, media as a row of thumbnails picked several at a time from
the library and ordered by dragging or ← and →.
