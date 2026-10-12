# space.json is made by the archive use case

Superseded by adr/2026-10-12-space-json-is-a-format-of-its-own.md
Superseded by adr/2026-10-12-json-is-converted-at-the-edges.md

*2026-09-27, restating a decision of 2026-09-25*

## Context

The web makes the JSON a request is answered with. The `space.json` inside a
space's archive is JSON as well.

## Decision

`usecases/archive` writes and reads `space.json` itself, not `web/presenters`.
It is koya's format for moving a space rather than an answer to a request, and
reading it back is checking it, which is the use case's job.

## Consequences

- The archive has JSON of its own for contents and media, apart from what the
  delivery API serves, and one can change without the other.
