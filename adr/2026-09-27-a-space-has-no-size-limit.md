# A space has no size limit

*2026-09-27, restating a decision of 2026-09-25*

## Context

A limit on the size of a space was considered, so that every space could be
moved. It would be a product limit set by how archives are built, and counting
contents and their history against it would refuse writes.

## Decision

A space has no size limit.

## Consequences

Whatever moves a space, whether export or import, must not need memory that
grows with the space.
