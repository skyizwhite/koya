# URL templates fill in the slug

*2026-10-10*

## Context

A model's `previewUrl` and `publicUrl` filled in `{CONTENT_ID}` and
`{DRAFT_KEY}` only, so a site whose pages live at their slug could not link the
editor to them.

## Decision

Both templates also fill in `{CONTENT_SLUG}`, the value of the model's slug
field. `publicUrl` takes the published slug, since it links what the site shows
now; `previewUrl` takes the draft's, since the preview reads the draft. When
the slug is blank, the link is not shown. A template that uses
`{CONTENT_SLUG}` on a model without a slug field is refused when it is
deployed.

## Consequences

- A slug changed in a draft moves the preview link at once and the published
  link only when it is published.
- A site's preview page can read the draft by the slug and the draft key alone,
  as [the delivery API finds it](2026-10-10-a-list-content-is-reached-by-its-slug.md).
