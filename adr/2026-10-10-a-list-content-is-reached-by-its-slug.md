# A list content is reached by its slug

*2026-10-10*

## Context

A site that puts a slug in its URLs read a content by filtering the list on the
slug field and taking the first result, and could not do even that for a
preview: a draft key is taken only by the read of one content, and the filter
looks at published data, so a draft's new slug found nothing. Making the id
editable instead, so that the id could be the URL, was weighed and set aside:
references, the history and webhook receivers all hold ids, and an id that
changed would cut them all.

## Decision

A slug is a second key of a list content, beside its id.

- A list model has at most one `slug` field, and an object model has none. A
  deploy that gives a model more is refused.
- A slug is unique within its model, always: the field has no `unique` option.
  The check is the one `unique` made, against the other contents' published
  data and drafts, a blank slug left out.
- A content is read by its slug at `GET /api/v1/{space}/lists/{model}/slugs/{slug}`,
  and read, saved and deleted at `/admin/api/{space}/lists/{model}/slugs/{slug}`.
  The id stays the key of everything else: publishing, references, the history,
  webhooks, the admin UI's URLs.
- The delivery API finds a content by its published slug, and with the
  content's draft key by its draft's slug too. A draft key that is not the
  content's finds it by its published slug only, so a draft's slug is not
  revealed. The admin API finds a content by either.
- A slug that more than one content holds finds none.

## Consequences

- Since the check covers drafts and published data alike, a slug names one
  content at most, so finding by either version is not ambiguous.
- Schemas stored before this lose `unique` on their slug fields when the server
  is upgraded, and an archive exported before this is imported without it.
  Contents stored before may share a slug, and a model may hold two slug
  fields: the upgrade leaves them as they are. Such a slug finds nothing, and a
  model with two slug fields finds nothing by slug, until they are put right; a
  content sharing a slug is refused on its next save until it is changed.
- A model's slug is kept beside each version's data when the content is
  written, so that finding by it is a lookup.
