# An archive is written and read by infra, one entry at a time

*2026-09-27, restating a decision of 2026-09-25*

## Context

An export built in memory held about twice the archive at once. A space large
enough ran the process out of heap, and SBCL stops rather than signals when that
happens, so every space went down with it.

## Decision

- The zip is written and read by infra, behind `ports/archives`. zippy copies an
  entry from its file and unpacks one on demand, a few kilobytes at a time.
- What is held in memory is `space.json` and one media file.
- The use case builds `space.json` and checks what is imported, and it never sees
  a path.

## Consequences

The memory an export or an import needs does not grow with the space.
