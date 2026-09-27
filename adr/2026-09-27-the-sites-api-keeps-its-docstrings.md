# The site's API keeps its docstrings

*2026-09-27*

## Context

`src/` has no docstrings. A site's developer, though, works in their own REPL,
with neither this repository's spec nor its source open, and reads what a
function does with `describe`.

## Decision

- Each symbol the `koya-sdk` package exports has a docstring.
- The readers of `koya-error` are named in its docstring, because a condition's
  reader carries none of its own.
- Nothing else in `koya-core` or `koya-sdk` has a docstring.
- `koya-spec/sdk/main` requires each one to be documented.

## Consequences

A symbol added to the site's API needs a docstring, or the spec fails.
