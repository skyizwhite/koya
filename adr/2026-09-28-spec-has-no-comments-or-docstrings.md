# spec has no comments and no docstrings

*2026-09-28*

## Context

`src/` has no comments and no docstrings, because they went stale unchecked
and a reader could not tell a true one from a stale one. `spec/` held about 70
lines of comments and about 25 docstrings, which had the same trouble: most
restated the lines below them or how a test was set up, and a few gave a
reason no assertion checked.

## Decision

- `spec/` has no comments and no docstrings, as `src/` has none.
- What a check means is said in its `testing` or `ok` description, which rove
  prints when it fails.

## Consequences

- What a spec says it checks is shown beside whether it held.
- A helper shared by spec files says what it is by its name and its arguments
  alone.
- A reason for how a test is built, which no assertion states, is not kept.
