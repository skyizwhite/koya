# Health is answered ahead of everything, from a table it reads

*2026-10-03*

## Context

`/health` was a page: it went through the session middleware, the page guard
and the whole HTML document, and every check wrote a line to the access log. It
ran `SELECT 1`, which never touches the database file, so a database that could
not be read still answered `ok`.

## Decision

- `/health` is mounted first, ahead of the access log, the session and the
  guards.
- It reads a table of the database. It answers 200 `{"status": "ok"}` when that
  works, and 503 with the error object, code `unavailable`, when it fails: JSON,
  as the APIs answer. It says nothing else, since anyone may ask.

## Consequences

- A health check opens no session and leaves nothing in the access log, however
  often it is asked.
- A database that is there but cannot be read takes the instance out of service.
- `/health` is no page, so it needs no `public-path`.
