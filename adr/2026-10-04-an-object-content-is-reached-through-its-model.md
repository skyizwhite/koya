# An object content is reached through its model

*2026-10-04*

## Context

An object model holds one content, and that content was reached like any other:
the admin API, the SDK and the admin UI took its id. A caller had to read the
model first to learn an id it had no use for, and the admin UI showed the
content under `…/{id}`, or under `…/new` while it had none, as if it were one
of many.

## Decision

An object model's content is part of the model, and is reached through the
model's own address:

- The admin API reads it at `GET /admin/api/contents/{space}/{model}`, saves a
  draft with `PATCH` there, and has `publish`, `unpublish`, `discard-draft` and
  `draft-key` under it. Every route with `{id}` answers `404` for an object
  model, and those object routes answer `404` for a list model.
- The first draft saved, or the first publish with data, makes the content.
  Until then there is nothing to read, and the read is a `404`.
- The admin UI edits it at the model's URL; `…/{id}` and `…/new` lead there.
- The Lisp SDK has functions that take the model and no id.

## Consequences

- One address does one thing for a model of either kind: an id is never half
  of the way to an object's content.
- `GET` on a model answers a list or a content, as the delivery API does.
- Its id still names it in webhooks, revisions and the history page, where it
  is what a stored record carries.
- A caller that changed an object content by id now gets `404`, and moves to
  the model's routes.
