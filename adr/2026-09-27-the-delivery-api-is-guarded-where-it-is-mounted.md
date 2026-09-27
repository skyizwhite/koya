# The delivery API is guarded where it is mounted

*2026-09-27*

## Context

`adr/2026-09-25-pages-are-guarded-where-they-are-mounted.md` brought the pages
in line with the admin API and the actions: each is guarded by a middleware
where it is mounted, and a route added later is covered without doing anything.

The delivery API was left out. Each of its two routes began with
`(require-delivery-key space)`, so a third route that forgot the call would have
answered anyone, and nothing would have noticed. The routes also imported
`web/auth` for it, which no other route needed.

## Decision

- **`*mw-delivery-auth*` (`web/auth`) guards the delivery API**, stacked on the
  API app inside CORS and the trailing-slash redirect. A request needs an
  `X-KOYA-DELIVERY-KEY` (401 without one or with a wrong one) for the space its
  path names (403 otherwise). Every route is `v1/<space>/...`; a path that
  names no space is no space of the key's, and is refused, as a management key
  is refused a path outside its space.
- **The routes check nothing.** `require-delivery-key` is gone.

## Consequences

- A delivery route added later is covered.
- Its refusals carry CORS headers, as the route's did, since CORS is outside the
  guard.
- What changes on the wire is what happens before a route is found:
  - A path that is no route, asked for without a key, is 401 where it was 404.
  - A trailing slash is redirected only for a request with a valid key.

  This is what the admin API already did.
