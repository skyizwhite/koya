# A reference is embedded only when include names it

*2026-09-27, restating a decision of 2026-09-20*

## Context

A content can refer to others, and a reader often wants them in the same
answer. A `depth` number would expand whatever references happen to be there,
to that depth.

## Decision

The delivery API returns references as ids. It embeds one only when `include`
names its path, such as `include=tags,author.avatar`. A path that is not a
reference field is refused.

## Consequences

A site that wants a reference embedded says which one, so nothing is fetched by
accident, and adding a reference field to a model does not grow the answers
that do not ask for it.
