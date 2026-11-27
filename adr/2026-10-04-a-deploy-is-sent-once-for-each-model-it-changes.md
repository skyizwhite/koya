# A deploy is sent once for each model it changes

*2026-10-04*

## Context

A deploy that removes a model deletes its contents, one that removes a field or
changes its type takes its values out of the stored data, and a rename changes
the URL or the keys the delivery API answers with. None of it sent anything, so
a site that rebuilds from webhooks went on serving what the delivery API no
longer had.

Sending each affected content as an event it already knows was weighed:
`delete` for a removed model's contents works, but a field taken out of a
published content is no publish, and the history keeps no entry for it, while
every event so far is an entry of the history
(`adr/2026-09-28-each-history-entry-is-sent-as-its-kind.md`).

## Decision

- A deploy that changes what the delivery API serves of a model is sent to the
  webhooks covering that model, once per model, as `deploy`: the model renamed,
  removed or of another kind, or a field of it renamed, removed or of another
  type.
- The payload has `id` and both `contents` `null`, and carries that model's
  changes as a plan shows them.
- A removed model goes to the webhooks of the deployed schema that cover its
  name. Adding something, changing options or webhooks, and a plan send
  nothing.

## Consequences

- A deploy is one entry of the deploy log, sent as its kind, as a write to a
  content is.
- A receiver that rebuilds per model handles it as it handles a publish; one
  that works per content has to read the model again.
- An import still sends nothing (`adr/2026-09-27-an-import-sends-no-webhooks.md`):
  it replaces the schema without deploying it.
