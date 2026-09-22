# A space is made in the admin UI, never by a deploy

*2026-09-22*

## Context

A schema document used to carry every space of the instance, and a deploy
replaced the lot. So a site's repository decided which spaces existed: deploying
from one site could delete another site's space, and a typo could grow an empty
one.

## Decision

A space is a tenant — it owns the contents, media, keys and webhook secret, and
outlives any one schema. It is created and deleted on the spaces page, and a
deploy addresses one that already exists: `PUT /admin/api/schema/{space}`, a
`404` when it does not.

The schema document lost its `spaces` key and is now one space's
`{koyaSchema, webhooks, models}`. The DSL lost `defspace`; `defmodel` no longer
takes a space name, and `koya:*space*` says where a deploy goes.

A space has a name and nothing else. The name is its id — it is in every URL and
in the delivery API — so there is nothing to edit.

## Consequences

One project, one space, and a site's repository cannot reach past its own. The
diff has no `add_space` or `remove_space` to consider.
