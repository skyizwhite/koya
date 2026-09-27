# Delivery keys and management keys are kept apart

*2026-09-27, restating a decision of 2026-09-22*

## Context

Delivery keys and management keys have the same columns, so one table with a
`scope` column would hold both.

## Decision

They keep separate tables, `delivery_keys` and `management_keys`. That their
columns are the same is a coincidence, and one table would move the guarantee
that a delivery key cannot deploy a schema into one `WHERE` clause that someone
can forget.

## Consequences

A delivery key is looked up only where delivery keys are, and cannot be taken
for a management key by a query that forgot its scope.
