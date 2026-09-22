# Writes check their origin, and the front door is bolted

*2026-09-20*

## Context

The admin UI and the admin API share a session cookie, so a page on another site
could drive the API in a logged-in browser. Before going on the public internet
the obvious ways in wanted closing.

## Decision

Every state-changing request — the UI's forms and the admin API alike — must
carry an `Origin` or `Referer` matching this server. The session cookie is
HttpOnly, SameSite=Lax, and Secure when the base URL is https.

With it: a maximum body size, a lockout after repeated failed logins, session
expiry, and no row for an empty session.

## Consequences

The defence does not rest on SameSite's default alone. A management key, which
carries no cookie, is unaffected by the origin check in practice because it is
sent by a program that sets its own headers.
