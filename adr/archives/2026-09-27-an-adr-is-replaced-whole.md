# An ADR is replaced whole, and one ADR holds one decision

Superseded by adr/2026-10-11-an-adr-holds-one-decision.md
Superseded by adr/2026-10-11-a-new-decision-replaces-an-adr-whole.md
Superseded by adr/2026-10-11-an-adr-is-not-edited-once-it-is-on-master.md

*2026-09-27*

## Context

An ADR replaced in part could not move to `adr/archives/`, because what still
held would go with it.

## Decision

- An ADR holds one decision.
- A new decision replaces an old ADR whole. Whatever of the old one still holds
  is written again as ADRs of its own, one per decision, and the old one moves
  to `adr/archives/`.
- An ADR is still not edited, apart from the `Superseded by` lines.

## Consequences

- The six ADRs that had been replaced in part were written again on 2026-09-27
  as one ADR per decision that still held, and moved to `adr/archives/` with the
  three that had been replaced whole.
- Replacing a decision can mean writing several ADRs at once.
