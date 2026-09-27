# A short owner secret turns logging in off, not the server

*2026-09-28*

## Context

The owner secret must be at least 32 characters, and instances made before
that rule may have a shorter one. Refusing to start would also stop the
delivery API, and with it the sites that read from the server, for a problem
that concerns only logging in.

## Decision

- With a shorter `KOYA_SECRET`, or none, the server starts and runs as usual,
  and says at startup that logging in is off.
- The login page says why and asks for nothing; the login action refuses even
  the short secret itself.
- Sessions already made keep working.

## Consequences

- Replacing the secret and restarting is all it takes. The secret is read from
  the environment and kept nowhere else, so nothing is migrated.
- Delivery keys, management keys and webhooks work throughout.
