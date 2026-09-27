# Failed logins lock an address out for a while

*2026-09-27, restating a decision of 2026-09-20*

## Context

The login page is open to anyone and asks for the owner's secret. Without a
limit, the secret can be guessed as fast as the server answers.

## Decision

- After five failed logins from one address, each within five minutes of the
  last, that address is refused, even with the right secret, until five
  minutes have passed since the last failure.
- A successful login clears the count.
- The count is kept in memory, not in the database.

## Consequences

- Guessing the secret from one address is slowed to a few tries every five
  minutes.
- A restart clears every count.
- The owner who mistypes five times waits too.
