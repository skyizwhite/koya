# An export is sent from a file and deleted once it is sent

*2026-09-27, restating a decision of 2026-09-25*

## Context

An export is as large as a space, and it holds the webhook secret and every
draft.

## Decision

- The export page answers with the archive's file and a header.
  `*mw-temporary-file*` hands the file to the server and deletes it once the
  server has it.
- Woo has opened the file by then and sends from what it opened. Hunchentoot has
  already sent it.

## Consequences

An archive does not stay on the disk after it is sent.
