# What is open is declared with public-path where it is defined

Superseded by adr/2026-10-01-what-is-open-is-declared-with-public-path.md

*2026-09-27, restating a decision of 2026-09-25*

## Context

The guards deny by default, and some paths must still be reachable without a
session. How those paths are named decides whether they can be found.

## Decision

- A path is let through without a session by `public-path`, called where the
  path is defined.
- The list is by path rather than by action, so that every guard can read the
  same list.
- Logging in is the only public action, because it is where a session comes
  from. It still has to come from htmx on this origin, so another site cannot
  log a browser in.

## Consequences

What is open can be found by looking for `public-path`.
