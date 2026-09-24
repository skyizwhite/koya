# The delivery API answers any origin

*2026-09-24*

## Context

A delivery key reads published content only, so it was always meant to be
safe to put in a front end. But the server sent no CORS headers. Because the key
travels in `X-KOYA-DELIVERY-KEY`, a browser sends a preflight `OPTIONS` before
the `GET`, and koya did not answer it. So content could be read only from a
server.

Declining to answer would not have limited the key to servers: CORS binds
browsers only, and curl or any server can send the key regardless. It would only
have kept sites that render in the browser from using the delivery API without
a proxy of their own.

## Decision

The delivery API (`/api` in full) answers the preflight itself, with `204`,
`Access-Control-Allow-Origin: *`, `Allow-Methods: GET`,
`Allow-Headers: X-KOYA-DELIVERY-KEY` and a day's `Max-Age`, without checking a
key. Every answer carries `Access-Control-Allow-Origin: *`, errors included, so a
page can read why a request failed.

Any origin, not a list per space. A list would protect nothing the key does not
already expose, and it would need a migration and a settings form. With `*` the
answer is the same for every caller, so there is no `Vary: Origin`.

The admin API and the admin UI send no CORS headers. The management key must
never be in a browser, and the check that writes come from this server's origin
(`adr/2026-09-20-writes-check-their-origin.md`) is unchanged.

## Consequences

A key shipped in a page's bundle can be read by anyone who loads the page. That
reveals no more than the page shows, but turning the key off means deploying the
site again with a new one. Browser reads bring every visitor to koya directly,
since its answers are `no-store`; reading from the site's server remains the way
to keep that load low. A draft key sent from a browser shows the draft to
whoever holds it, so it belongs only on a preview page.

A list of origins per space can still be added later if a site asks for one.
