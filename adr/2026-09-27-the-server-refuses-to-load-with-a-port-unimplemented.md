# The server refuses to load while a port has no method

*2026-09-27, restating a decision of 2026-09-25*

## Context

A port function that nothing implemented went unnoticed until a request called
it.

## Decision

When `koya-server/main` loads, infra has loaded too. It then calls okite's
`ensure-implemented` on `+ports+`, the list in `usecases/ports/main`, and stops
loading if any generic function has no method.

## Consequences

- A missing implementation stops loading at the REPL, in the image build and in
  `just spec` alike.
- A use case that is called without infra loaded still fails at run time, with
  "no applicable method".
