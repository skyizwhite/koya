# A port is a generic function with one unspecialized method

*2026-09-27, restating a decision of 2026-09-25*

## Context

A port declared with `declaim ftype` gave no lambda list, and it silenced the
warning for a function that nothing defined.

## Decision

- **A port function is a `defgeneric`.** Its implementation is a `defmethod`,
  which CLOS checks against the lambda list when the implementation loads.
- **The method is not specialized.** There is one implementation, and most
  arguments are strings, some of them NIL, so there is nothing to dispatch on.
  The specs run the same implementation over an in-memory SQLite.

## Consequences

- A method whose lambda list does not match its port fails when it loads.
- Swapping implementations would take a store object as the first argument.
  Nothing needs that today.
