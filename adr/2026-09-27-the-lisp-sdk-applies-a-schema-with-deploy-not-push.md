# The Lisp SDK applies a schema with deploy, not push

*2026-09-27, restating a decision of 2026-09-20*

## Context

The function that sends a site's schema to the server needs a name. `push` is
the obvious one beside `pull`, but `cl:push` exists.

## Decision

The function is `koya-sdk:deploy`.

## Consequences

A site's package can use `cl` and `koya-sdk` together without shadowing
anything.
