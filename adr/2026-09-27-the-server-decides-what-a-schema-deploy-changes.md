# The server decides what a schema deploy changes

*2026-09-27, restating a decision of 2026-09-20*

## Context

A site sends its whole schema to deploy it. Something has to compare it with
what the server holds, and say whether the change can hide or invalidate stored
content. That could be done in each client or once on the server.

## Decision

- The diff is computed on the server, with `koya-core/diff`, and returned as
  data: the plan endpoint answers the changes, and a deploy answers what it
  applied.
- A deploy whose changes are destructive is refused with
  `409 destructive_changes`, carrying the changes, unless `force` is given.

## Consequences

- The judgement of what is destructive lives in one place, whichever client
  sends the schema.
- The confirmation prompt lives in the client, where a person is: it shows the
  refused changes and sends the deploy again with `force`.
