# koya-server/main is the composition root

*2026-09-27, restating a decision of 2026-09-25*

## Context

The use cases call ports, and infra implements them. Something has to load the
implementation, and it has to be outside the layers so that none of them
reaches infra.

## Decision

`koya-server/main` is the only module that loads `infra/`. It also starts the
web app on top.

## Consequences

- Nothing but `main` depends on `infra/`, and the layers spec holds it to that.
- Anything that loads `koya-server` gets the implementations through `main`. A
  file loaded on its own at the REPL does not.
