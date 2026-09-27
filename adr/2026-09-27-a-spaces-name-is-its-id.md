# A space's name is its id

*2026-09-27, restating a decision of 2026-09-22*

## Context

A space is in every admin URL and every delivery API path. It could have an id
and a separate name to show.

## Decision

A space has a name and nothing else. The name is its id, and it cannot be
edited.

## Consequences

There is nothing to edit about a space. A URL that names a space keeps working
for as long as the space exists.
