# Turning two-factor on or off ends every other session

*2026-10-04*

## Context

Sessions live in the database and outlast restarts, and nothing ended one but
logging out or a day without use. Turning two-factor login on is how the owner
answers a secret they fear has leaked, yet a session opened with that secret
went on as before. A browser left logged in elsewhere could not be ended from
the admin UI at all.

## Decision

- Turning two-factor login on or off ends every session but the one that did
  it.
- **Log out other sessions** on the settings page does the same at any time.

## Consequences

- The owner keeps working where they made the change; everywhere else logs in
  again, with a code when it is now on.
- There is no list of sessions to pick from: with one owner, "all but this one"
  is the choice there is.
