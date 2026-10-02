# The APIs take keys, and the admin UI takes the session

*2026-10-03*

## Context

The admin API took the owner's session cookie as well as a management key, so
that it could be called from the logged-in browser. Nothing calls it that way:
the admin UI works through its own pages and actions, and the SDKs send a
management key. Taking the cookie meant the admin API had to defend against
what a cookie brings: a page elsewhere writing through the owner's browser.

## Decision

- The delivery API and the admin API are web APIs, and each takes its key in a
  header: a delivery key, or a management key as a Bearer token. Neither reads
  the session.
- The session is the admin UI's: its pages and its actions, which answer HTML.

## Consequences

- A request to the admin API is the key's, whatever cookie comes with it, and
  is named by the key's label.
- No browser sends a key on its own, so the admin API needs no defence against
  cross-site writes, and does not check where a write comes from.
- `/admin/api/me` describes the key: the space it reaches and the version.
