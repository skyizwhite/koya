# A repeater holds rows of custom fields

*2026-10-05*

## Context

A page's blocks, an FAQ or a list of links is a list of small objects, and a
page's blocks are of different kinds: a heading, a paragraph, an image. Custom
fields (`adr/2026-10-05-custom-fields-are-named-sets-of-fields.md`) give a named
shape to one object; a repeater lists them. Its rows could hold built-in fields
too, a bare rich text or a bare image beside the objects.

## Decision

A `repeater` names the custom fields its rows can be, and every row is one of
them: an object naming its custom field in `fieldId`, beside that custom field's
fields. A row of a rich text alone is a custom field holding one rich text, named
for what it is, `body` or `quote`, since a site draws rows by that name and two
rows of the same built-in type are often drawn apart.

Every row has one shape, so validation, the diff, delivery, the editor and the
TypeScript types each know one kind of row. A list of one plain kind, a gallery
of images, is `many` on that field rather than a repeater.

In the editor, a row is added by the server: the add button asks for one row of
the chosen custom field and appends what comes back, so the row's controls,
rich text included, start as any drawn on the page do. Moving, dragging and
removing rows happen in the browser, and the form sends each row's key in the
order the rows stand.

## Consequences

A path into a repeater names the row by its index in content
(`blocks[2].text`) and by its custom field in a schema change
(`page.blocks[heading].text`). Adding a row costs a request; the rows already on
the page are untouched by it.
