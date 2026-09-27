# Domain errors carry no HTTP status

*2026-09-27, restating a decision of 2026-09-25*

## Context

Errors that carried an HTTP status tied the use cases to HTTP, and the bulk
actions had to catch an API error to go on.

## Decision

- `domain/errors` defines the kinds of failure: `not-found`, `conflict`,
  `invalid-input`, `rejected` and `too-large`. Each has the code that the APIs
  carry in their error object.
- The web turns a kind into a status in one place, `error-status` in `web/http`.
  Both APIs and the actions' refusals use it.

## Consequences

- A use case fails the same way whoever calls it, whether a page, an API route
  or the REPL.
- An error code is part of what an API caller relies on, so a new code is an API
  change.
