# Every deploy that changes something is logged

*2026-09-27, restating a decision of 2026-09-23*

## Context

A schema is deployed from a site's repository, so the server was the one place
that could not say what its schema used to be. "When did that field go" meant
reading someone else's git history.

## Decision

- A deploy that changes something writes a row: what it changed, who sent it,
  and when. It is written in the same transaction as the change itself.
- A deploy that changes nothing is not an event and writes no row.
- `/s/{space}/deploys` reads the log back and draws each change as the line
  `plan` prints for it.

## Consequences

- The log and the schema cannot disagree: a change is logged if and only if it
  was made.
- Deploying the same schema again leaves the log as it was.
