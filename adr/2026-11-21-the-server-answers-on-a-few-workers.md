# The server answers on a few workers

*2026-11-21*

## Context

Woo ran with one event loop, so a request ran only once the one before it had
finished: a large media file being sent, or an upload being read, held up the
admin UI and both APIs. The database is one SQLite connection behind one lock
(`adr/2026-09-27-koya-stores-its-data-in-sqlite.md`), so more threads do not
make it answer faster; what they let run side by side is the work around it.
Several connections, so that reads need not wait for one another, would change
what a transaction can rely on and is not taken up here.

## Decision

- Woo runs `KOYA_WORKERS` worker threads, two when it is not set. One that is
  not a whole number of 1 or more stops the server before it starts, as a bad
  port does (`adr/2026-10-04-a-bad-base-url-or-port-stops-the-server.md`).
- It is an environment variable, not a setting in the admin UI: the server
  needs it before it opens the database
  (`adr/2026-09-27-product-settings-live-in-the-admin-ui.md`).
- What reads a value and then writes from it does so in one transaction, which
  holds the database lock until it ends. Logging in is one: the count of wrong
  two-factor codes and the step a code was last used in stay what
  `adr/2026-10-04-wrong-two-factor-codes-are-limited-each-step.md` says when
  logins arrive together.

## Consequences

- A slow request no longer stops the others, except where they wait for the
  database.
- Past a few workers nothing is gained, since every request that reads data
  queues on the same lock.
- Code that keeps state outside the database runs on several threads at once
  in production, as it already did under Hunchentoot in development, and holds
  a lock of its own.
