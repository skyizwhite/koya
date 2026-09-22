# Every deploy is logged, as its changes only

*2026-09-23*

## Context

A schema is deployed from a site's repository, so the server was the one place
that could not say what its schema used to be. "When did that field go" meant
reading someone else's git history.

## Decision

A deploy that changes something writes a row: what it changed, who sent it, and
when, in the same transaction as the change itself. A deploy that changed
nothing is not an event. `/s/{space}/deploys` reads it back and draws each
change as the line `plan` prints for it.

The schema document is not kept, only the changes, and the newest 100 per space.

Who is stored as `owner` or `key:<label>` — what the server knew — and the
wording a page puts around it is the page's, so it can be reworded later without
the rows already written keeping the old words.

## Consequences

The log answers what changed, not what the schema was; the schema itself is read
from the space page or with `pull`. If it should ever grow into rollback, that
is when the document earns a column.
