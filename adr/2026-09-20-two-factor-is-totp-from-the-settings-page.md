# Two-factor login is TOTP, turned on from the settings page

*2026-09-20*

## Context

The admin UI is reachable from the internet and is defended by one secret in the
environment. A second factor is worth having; requiring a REPL to set one up
means it will not be set up.

## Decision

TOTP. The settings page shows a QR code, takes a code from the authenticator to
confirm it works, and only then stores the secret in `settings` and turns it on.
`KOYA_TOTP_SECRET` overrides it for setup from outside.

## Consequences

Two-factor is off until someone chooses it, and cannot be turned on by accident
in a way that locks the owner out — the code has to be proved first.
