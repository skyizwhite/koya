# Webhooks are declared on the space, in one list

*2026-09-27, restating a decision of 2026-09-22*

## Context

Webhooks could be declared on the space or on each model. Declared in both
places, reading "what fires where" means reading the whole schema.

## Decision

- Every webhook is the space's, declared together in `defwebhooks`.
- `:only` narrows one to a model or a list of them. Without it, a webhook covers
  every model, including models added later.

## Consequences

Which hook goes where is one list.
