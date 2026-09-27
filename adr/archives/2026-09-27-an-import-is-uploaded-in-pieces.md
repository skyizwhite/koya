# An import is uploaded in pieces, and made in one transaction

Superseded by adr/2026-09-27-an-import-is-sent-in-pieces.md
Superseded by adr/2026-09-27-an-import-is-made-in-one-transaction.md

*2026-09-27, restating a decision of 2026-09-25*

## Context

An import taken as one request body limited the size of a space that could
move. Woo reads a whole body before any middleware sees it, so that limit could
not simply be raised.

## Decision

- The import dialog cuts the file into pieces of `+import-piece-bytes+` (16 MB).
  It sends each piece to an action, which adds it to the end of an upload at the
  offset the piece names. A piece that does not follow is refused, with where the
  upload stands.
- A last action imports the upload in one transaction, while a bar shows the
  upload and then that the server is at work.

## Consequences

- No request of an import is larger than any other.
- While an import is made, the instance answers nothing else, the delivery API
  included, because the transaction holds the store. It is kept that way so that
  an import is all or nothing, and moving a space is rare.
- An import interrupted by a restart starts again, because action URLs change
  with the process.
