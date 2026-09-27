# An import is uploaded in pieces

*2026-09-27, restating a decision of 2026-09-25*

## Context

An import taken as one request body limits the size of a space that can move.
Woo reads a whole body before any middleware sees it, so that limit cannot
simply be raised.

## Decision

- The import dialog cuts the file into pieces of `+import-piece-bytes+`
  (16 MB). It sends each piece to an action, which adds it to the end of an
  upload at the offset the piece names.
- A piece that does not follow is refused, with where the upload stands.
- A bar shows the upload, and then that the server is at work.

## Consequences

- No request of an import is larger than any other.
- An import interrupted by a restart starts again, because action URLs change
  with the process.
