# A key's prefix says what kind it is

*2026-09-27*

## Context

A key can turn up somewhere it should not, such as a log, a repository or a
pasted snippet. Whoever finds it should be able to tell that it is koya's, and
whether it only reads published content or can deploy a schema.

## Decision

A delivery key starts with `koya_`, and a management key starts with
`koya_mgmt_`.

## Consequences

- A leaked key can be found by searching for the prefix, and its kind is known
  without asking the server.
- A delivery key never starts with `koya_mgmt_`.
