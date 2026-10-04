# Lists and objects are named apart

*2026-10-05*

## Context

A `list` model has any number of contents and an `object` model exactly one, and
what can be done to them differs. Both were reached at one address,
`…/{model}`, which answered a page for one kind and a content for the other.
The operations were named `content` for both kinds in one place and for a list's
alone in another, and the same operation had a different name in the openapi
document, the Lisp SDK and the use cases. A name did not say which kind it was
for, and a route could not be named for both kinds at once.

## Decision

- A `list` model is a **list**, and its contents are **list contents**. An
  `object` model's one content is its **object**.
- Each kind has its own routes: `lists/{model}` and `lists/{model}/{id}`, and
  `objects/{model}`, in the delivery API and in the admin API. A model of the
  other kind is not found there (`404`).
- An operation is named for its kind with those words, the same in every place:
  `getList`, `getListContent`, `getObject` in the delivery API;
  `getAdminList`, `createAdminListContent`, `updateAdminListContent`,
  `updateAdminObject` and so on in the admin API. The Lisp SDK spells them
  `get-list`, `get-list-content`, `get-object`, and the admin API's with an
  `admin-` prefix: `admin-get-list`, `admin-update-object`.
- `content` alone names what is true of both kinds: webhooks, revisions, a
  content's status.

## Consequences

- One address does one thing; no response is one shape or another by the
  model's kind.
- The Lisp SDK's admin functions are longer, and they do not collide with the
  delivery API's.
- The TypeScript client generated from the openapi document takes the new
  names.
