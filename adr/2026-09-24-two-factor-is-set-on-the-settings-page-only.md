# Two-factor login is set on the settings page only

*2026-09-24*

## Context

The second factor was turned on from the settings page, and `KOYA_TOTP_SECRET`
could set it from outside instead, with `(koya-server:totp-setup)` in the
server's REPL to make the value (`adr/2026-09-20-two-factor-is-totp-from-the-settings-page.md`).
Nobody sets it that way, and the published image has no REPL to run
`totp-setup` in. Two ways to hold one secret meant the settings page had to
explain which was in force and refuse to change the other.

## Decision

TOTP, turned on from the settings page, which shows a QR code and stores the
secret in `settings` only once a code from the authenticator has proved it.
There is no environment variable for it and no REPL function to make one.

## Consequences

The secret is in the database, and a backup of `/data` carries it. An owner who
has lost the authenticator deletes the `totp_secret` row of `settings` with the
server stopped, as ADMIN-UI.md says; the owner secret alone then logs in.
