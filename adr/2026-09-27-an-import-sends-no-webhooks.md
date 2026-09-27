# An import sends nothing to the webhooks

*2026-09-27, restating a decision of 2026-09-23*

## Context

The contents an import writes are not being published. They are being put back.

## Decision

An import sends nothing to the space's webhooks.

## Consequences

A webhook receiver sees nothing of an import. The contents it is told about
afterwards are the edits made after the import.
