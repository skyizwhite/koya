# An ADR is not edited once it is on master

*2026-10-11*

## Context

An ADR was never edited, apart from its `Superseded by` lines. A branch often
writes an ADR early and learns more before it is merged: a review finds a wrong
figure, or a later commit on the same branch changes the decision. Replacing
such an ADR would leave `adr/archives/` holding drafts that were never on
`master`, and Superseded lines that point between files of one change.

## Decision

An ADR is not edited once it is on `master`, apart from its `Superseded by`
lines. Until then it is a draft of the branch that adds it, and is edited,
renamed or deleted as the work goes.

## Consequences

- What `master` has recorded is never rewritten; a change to it is a new ADR.
- `adr/archives/` holds only decisions that were once on `master`.
