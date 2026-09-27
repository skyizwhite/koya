# A write that names its origin must name this server

*2026-09-27, restating a decision of 2026-09-20*

## Context

The admin UI and the admin API share a session cookie, so a page on another site
could drive them in a logged-in browser.

## Decision

- A POST, PUT, PATCH or DELETE to the admin API or to an action is refused with
  403 when its `Origin`, or its `Referer` without an `Origin`, is neither this
  server's host nor koya's public URL.
- A request that carries neither header is let through.
- The check is part of the guard where the admin API and the actions are
  mounted.

## Consequences

- The defence does not rest on the cookie's SameSite alone.
- A browser sends `Origin` with every cross-site write, so a page elsewhere
  cannot write. A program with a management key sends no cookie and sets its own
  headers, and is not affected.
