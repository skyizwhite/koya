# `false` and `[]` are values, not blanks

*2026-09-20*

## Context

jzon reads JSON `false` as `NIL`, which is also the empty list and also "no
value" in Lisp. A required boolean that is `false`, and a required `:many` field
that is `[]`, look the same as a field nobody filled in.

## Decision

Blank is `null`, a whitespace-only string, or `[]` on a `:many` field —
nothing else. A boolean is exempt from `required`: missing or null means
`false`.

## Consequences

`false` is storable and stays stored. A required checkbox cannot be a
requirement to tick it, which is the right reading of `required` on a boolean
anyway.
