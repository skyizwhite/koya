# The spec is written first, and the code and docs follow it

*2026-09-27*

## Context

What koya does was said in three places: the tests, the comments and `docs/`.
None of them was the one the others followed, and nothing checked that they
agreed.

## Decision

- The spec is the tests in `spec/`, the `koya-spec` system, run with
  `just spec`. It was `tests/`, `koya-tests` and `just test`.
- A change starts as a spec that fails. The implementation is written to pass
  it, and `docs/` is written from what it says.
- The spec depends on neither of them: nothing under `spec/` reads `docs/`.

## Consequences

- To learn what koya does, read `spec/`. To learn how, read `src/`. To learn
  why it is this way and not another, read `adr/`.
- `docs/openapi.yaml` still changes with the API, because the TypeScript client
  is generated from it. It follows the spec, and nothing checks it against the
  server.
