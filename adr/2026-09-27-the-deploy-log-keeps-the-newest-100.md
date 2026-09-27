# The deploy log keeps the newest 100 deploys of a space

*2026-09-27, restating a decision of 2026-09-23*

## Context

A log that is never trimmed grows with every deploy for as long as the space
lives.

## Decision

The deploy log keeps the newest 100 deploys per space (`+deploys-kept+`). Writing
a new one deletes those past it.

## Consequences

The log is bounded, and the oldest deploys are lost first.
