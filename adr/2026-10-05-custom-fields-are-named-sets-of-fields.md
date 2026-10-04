# Custom fields are named sets of fields

*2026-10-05*

## Context

An FAQ, a list of links, a spec sheet or a page's blocks are small objects
inside one content. Without a way to write them, each needed a model of its own
and references to it, which is hard to edit and leaves stray contents behind.
The first proposal was a `group` field: a list of objects of one shape,
declared inside the field. It cannot hold a page's blocks, whose rows have
different shapes, and a shape used by two models had to be written twice.

## Decision

The schema declares **custom fields** beside its models: a name and a set of
built-in fields. A model uses one as a field of type `custom`, whose value is an
object of those fields. A **repeater**, the next step, will be a list of rows,
each one of the custom fields it allows, named in the row by `fieldId`.

Custom fields belong to the space, not to a model, so that a shape such as SEO
metadata or a link card is declared once and used by any model. A change to one
is therefore a change to every model that uses it, and the diff shows it there,
at `model.field.subfield`, with the destructive and tightening checks a
top-level field gets.

A custom field holds built-in fields only. Nothing nests deeper than a
repeater of custom fields, so the editor, the history and the delivery API each
have one known shape to draw. `slug` and `unique` stay at the top: a value
inside an object is no address and no key.

A model's stored definition names its custom field and does not copy it; the
schema gives each `custom` field the custom field's fields when it is put
together, so whatever reads a model reads them without the schema at hand.

The admin UI does not list custom fields as it lists models. They are part of
the schema written in the site's repository; the admin UI only draws them where
a model uses them.

## Consequences

A rename of a custom field or of a field inside one is a removal and an
addition until `was` reaches inside. Filters and orders do not reach inside a
custom field; only `contains` and `not_contains` read its text, as `q` does.
