# The server answers on a few workers

*2026-11-21*

## Context

Woo ran with one event loop, so a request ran only once the one before it had
finished. The database is one SQLite connection behind one lock
(`adr/2026-09-27-koya-stores-its-data-in-sqlite.md`), but most of what a large
request costs is outside it: encoding a delivery response of a page of
contents, drawing an admin page. Measured with 20 clients at once, a 100 KB
delivery list went from 212 requests a second on one worker to 321 on two and
436 on four, and no further on eight; an admin content list went from 83 to
179 on four. A small delivery request stayed near 1,200 a second whatever the
number, since there the lock is the limit. Several connections, so that reads
need not wait for one another, would change what a transaction can rely on and
is not taken up here.

## Decision

- Woo runs `KOYA_WORKERS` worker threads, four when it is not set. One that is
  not a whole number of 1 or more stops the server before it starts, as a bad
  port does (`adr/2026-10-04-a-bad-base-url-or-port-stops-the-server.md`).
- It is an environment variable, not a setting in the admin UI: the server
  needs it before it opens the database
  (`adr/2026-09-27-product-settings-live-in-the-admin-ui.md`).
- What reads a value and then writes from it does so in one transaction, which
  holds the database lock until it ends. Logging in is one: the count of wrong
  two-factor codes and the step a code was last used in stay what
  `adr/2026-10-04-wrong-two-factor-codes-are-limited-each-step.md` says when
  logins arrive together. Creating a space is another, so that two at once with
  one name make one space and a conflict.
- The image stops the server with SIGQUIT. Woo lets its workers finish on it,
  and on SIGTERM kills them, which under load can leave the process hung.

## Consequences

- Large responses are made side by side, up to the host's cores; on a host
  with fewer than four, the extra workers cost a little switching and gain
  nothing.
- Requests that are mostly reading data still queue on the one lock, and a long
  transaction such as an import still pauses every request.
- Woo hands connections to workers in turn, so a small request can wait behind
  a large one on its worker.
- Code that keeps state outside the database runs on several threads at once
  in production, as it already did under Hunchentoot in development, and holds
  a lock of its own.
