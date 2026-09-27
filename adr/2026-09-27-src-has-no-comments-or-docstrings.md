# src has no comments and no docstrings

*2026-09-27*

## Context

`src/` held about 650 lines of comments and about 420 lines of docstrings. Some
said again what the lines below them did. Others carried what the code could
not say: a constraint, a trap, a reason. They had to change whenever the code
did, nothing checked that they had, and a reader could not tell a comment that
was still true from one that had gone stale.

## Decision

- `src/` has no comments and no docstrings, and that includes the header of the
  generated `schema.sql`.
- What the code must keep doing is a spec. A reason that neither the spec nor
  the code can carry, such as something that only happens in the saved
  executable, is an ADR.
- The one exception is the site's API; see
  [the site's API keeps its docstrings](2026-09-27-the-sites-api-keeps-its-docstrings.md).

## Consequences

- The comments that held a constraint became specs: failed writes and
  rolled-back transactions leave nothing behind, a failed login does not say
  which factor was wrong, a webhook goes out after the commit, no space's DOM
  ids are another's, and more.
- A port's promise, which its `:documentation` used to state, is now what the
  specs of its callers require.
- `describe` and the editor show no docstrings for the server's functions.
