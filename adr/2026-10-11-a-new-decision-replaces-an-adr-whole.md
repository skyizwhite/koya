# A new decision replaces an ADR whole

*2026-10-11, restating a decision of 2026-09-27*

## Context

An ADR replaced in part could not move to `adr/archives/`, because what still
held would go with it, and a reader had to work out which half was true.

## Decision

A new decision replaces an old ADR whole. Whatever of the old one still holds
is written again as ADRs of its own, one per decision, and the old one moves to
`adr/archives/`.

## Consequences

An ADR in `adr/` is true as a whole, and one in `adr/archives/` is history.
