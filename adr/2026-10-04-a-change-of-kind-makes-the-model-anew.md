# A change of kind makes the model anew

*2026-10-04*

## Context

Changing a model from `list` to `object` needs `force` but changed no data. The
object then showed the oldest of its contents, and the others could not be
opened in the admin UI while they still counted for `unique` checks and for
references. Keeping one by a rule (the newest published) would have the server
choose which content survives; refusing while there were several would have the
owner delete all but one by hand before a deploy.

A list and an object hold contents differently, and an object is not a list of
one with the rest hidden.

## Decision

Changing a model's `kind`, either way, deletes its contents and their history in
the deploy's transaction, as removing the model and adding it again under the
same name would. The plan says so in the change's description.

## Consequences

- `force` means what it says for a kind as it does for a removed model or field.
- An object turned into a list does not keep its one content, although it could;
  one rule for both ways is easier to foresee than the more useful half of it.
- References from other models to the deleted contents are left pointing at
  nothing, as after removing a model.
- Receivers hear of it as a `deploy` of the model
  (`adr/2026-10-04-a-deploy-is-sent-once-for-each-model-it-changes.md`).
