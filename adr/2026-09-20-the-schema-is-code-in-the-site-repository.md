# The schema is code in the site's repository

*2026-09-20*

## Context

The schema could live in the CMS, edited through its admin UI, as most of them
do. But the site that consumes it is already a Lisp project under git, and the
shape of its content is part of how it is built.

## Decision

A site declares its models with `defmodel` in its own repository. The macro
builds plain data; the client serializes it to JSON and sends it. `plan` shows
what would change, `deploy` applies it, `pull` reads back what the server holds.

The diff is computed on the server, not in the client, and returned as data.
A change that can hide or invalidate stored content is refused with
`409 destructive_changes` unless `force` is given.

The reflecting function is called `deploy`, not `push`: `cl:push` exists and is
not worth shadowing.

## Consequences

The schema is reviewed and reverted like the rest of the site. The admin UI
shows it but cannot edit it.

Clients in other languages stay possible, because the wire format is JSON and
the reasoning is the server's. The confirmation prompt lives in the client,
where a person is; the judgement of what is destructive lives in one place.
