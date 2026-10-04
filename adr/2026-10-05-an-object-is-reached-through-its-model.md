# An object is reached through its model

*2026-10-05*

## Context

An object model holds one content, its object. A caller that reached it by an
id had to read the model first to learn an id it had no use for, and a create
could only make the object once, so a second create had to be refused.

## Decision

- An object is reached at its model's address, with no id: the admin API reads
  it at `GET /admin/api/{space}/objects/{model}`, saves a draft with `PATCH`
  there, and has `publish`, `unpublish`, `discard-draft` and `draft-key` under
  it. The delivery API reads it at `GET /api/v1/{space}/objects/{model}`.
- It is not created. The first draft saved, or the first publish with data,
  makes it; until then there is nothing to read, and the read is a `404`.
  Two first writes at once make one object, and the other is refused with
  `409 object_exists`.
- The admin UI edits it at the model's URL; `…/{id}` and `…/new` are not found
  for an object model.
- The Lisp SDK's functions for it take the model and no id.

## Consequences

- An id is never half of the way to an object.
- Its id still names it in webhooks, revisions and the history page, where it is
  what a stored record carries.
