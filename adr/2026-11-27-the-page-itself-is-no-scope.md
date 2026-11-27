# The page itself is no scope

*2026-11-27, restating a decision of 2026-11-27*

## Context

State could be held by one scope around the whole page, or only where a part of
the page needs it. Nagi keeps no state across the page: an element outside any
scope keeps its requests and their state to itself.

## Decision

The page itself is no scope. State is held only where a part of the page needs
it.

## Consequences

- Parts of a page share no state, and one part's requests do not cancel
  another's.
- An element that only asks or follows needs no scope around it.
