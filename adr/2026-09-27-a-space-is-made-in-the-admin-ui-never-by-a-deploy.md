# A space is made in the admin UI, never by a deploy

*2026-09-27, restating a decision of 2026-09-22*

## Context

If a schema document carried every space of the instance and a deploy replaced
the lot, a site's repository would decide which spaces exist. Deploying from one
site could delete another site's space, and a typo could grow an empty one.

## Decision

- A space is a tenant. It owns the contents, media, keys and webhook secret, and
  outlives any one schema.
- A space is created and deleted on the spaces page of the admin UI.
- A deploy addresses one space that already exists,
  `PUT /admin/api/schema/{space}`, and gets a `404` when it does not.
- The schema document is one space's `{koyaSchema, webhooks, models}`. A site
  names the space it deploys to with `koya-sdk:*space*`.

## Consequences

One project, one space, and a site's repository cannot reach past its own. A
deploy's changes never add or remove a space.
