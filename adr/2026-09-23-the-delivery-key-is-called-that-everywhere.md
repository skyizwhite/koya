# The delivery key is called that everywhere, including on the wire

*2026-09-23*

## Context

The key that reads the delivery API was called an API key in some places and a
delivery key in others: the admin UI and the documentation said delivery key,
the client's own variables said api key, and the header, the table and the
package said `api_key`. Two names for one thing, and the reader has to learn
both.

## Decision

Delivery key, everywhere it is read or written: `KOYA_DELIVERY_KEY`,
`koya:*delivery-key*`, `create/list/delete-delivery-key`, the OpenAPI summaries,
the 401 and 403 the delivery API answers with, the `X-KOYA-DELIVERY-KEY` header,
the `delivery_keys` table and the `db/delivery-keys` package.

The old header is not accepted. The callers are koya's own client and one site,
so a transitional period would cost more than switching.

## Consequences

Deploying this breaks a site sending the old header until it is updated: deploy
koya, then `qlot update koya` and redeploy the site.

Nothing in the repository now names another CMS, here or in the reasons behind
older decisions, which say "the source we migrated from" instead.
