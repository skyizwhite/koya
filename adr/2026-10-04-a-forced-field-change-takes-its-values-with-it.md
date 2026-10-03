# A forced field change takes its values with it

*2026-10-04*

## Context

A deploy that removed a field, or changed its type, with `force` replaced the
stored schema and left every content's data as it was. The old values went on
being delivered, failed validation on any write that merged onto them, and came
back under a new type when a field of the same name was added again.

Two ways out were weighed: take the values out of the stored data when the
field goes, or leave them and have every reader look only at the keys the model
declares. The second keeps them in the history for a restore, but a restore
worth having would also have to bring the field back into the schema, and every
reader of content data would carry the filter.

## Decision

Removing a field or changing its type takes that field's values out of every
published object, draft and revision of the model, in the deploy's transaction.
Data already stored with keys its model does not declare is cleaned the same way
once, by a migration.

## Consequences

- `force` means what it says for a field, as it already did for a model, whose
  contents go with it.
- Stored data holds only declared fields, so delivery, partial writes and
  validation need no filter, and a field added under an old name starts empty.
- A removed field's values cannot be restored from the history; bringing them
  back means deploying the field again and entering them again.
