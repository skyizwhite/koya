# A model names the field that labels its contents

*2026-09-23*

## Context

Wherever the admin UI had to show one content among others — a reference
preview in a list, the options of a reference dropdown, a reference in the
history — it took the content's first non-empty `:text` or `:slug` field. That
was a guess about someone else's schema: the first text field of one model is
its title, of another a subtitle, an SKU or a note, and it changes whenever the
fields are reordered.

## Decision

A model declares its label: `(defmodel blog (:kind :list :label title) …)`,
`"label": "title"` on the wire. It must name a `:text` or `:slug` field of the
model; a deploy where it names anything else — a field that was removed, or
renamed without the label following — is refused with the rest of the schema's
cross-reference errors.

A content is shown by the value of that field, and by its id when the model
declares none or the value is empty. Nothing is guessed.

Like the URL templates it sits beside, the label belongs to the schema rather
than to the settings page: it says what a model's fields mean, which only the
site's repository knows, and a setting kept apart from the schema could name a
field the next deploy took away.

## Consequences

A schema deployed before this has no labels, so its references show ids until
`:label` is added and deployed. Changing it is an ordinary, non-destructive
options change in `plan`.
