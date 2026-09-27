# The web reaches the ports through the use cases

*2026-09-27, restating a decision of 2026-09-25*

## Context

Twenty-four pages, components and API routes called the store directly, so
rules lived in route files and a page could bypass what a use case checks.

## Decision

- The web calls use cases, not ports. The one exception is `ports/presenters`,
  which the web implements.
- Where a use case has nothing to add to a port function, it re-exports that
  function rather than wrapping it. `usecases/media` does this with
  `find-media` and `list-media`.

## Consequences

- There is one way from a request to the store, and it goes through the rules.
- The layers spec fails on a web module that imports a port.
