# The session cookie is HttpOnly and SameSite=Lax, and Secure over https

*2026-09-27, restating a decision of 2026-09-20*

## Context

The owner's session cookie is what the admin UI and the admin API trust. A
script that could read it, a cross-site request that carried it, or a plain-http
request that exposed it would each give it away.

## Decision

The session cookie is HttpOnly and SameSite=Lax. It is Secure when koya's public
URL is https.

## Consequences

- No script on a page can read the session.
- A cross-site POST does not carry it, whatever the origin check does.
- An instance on plain http, such as one in development, still works.
