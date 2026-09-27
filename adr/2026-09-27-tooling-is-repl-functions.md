# Tooling is REPL functions, not commands

*2026-09-27, restating a decision of 2026-09-20*

## Context

Development here happens in a REPL attached to a running image. Anything offered
as a shell command has to start its own Lisp, load the system and exit.

## Decision

- What developers and operators need is a function: `koya-server:start`,
  `stop`, `reload` and `write-schema-snapshot`, and on the site's side
  `koya-sdk:plan`, `deploy` and `pull`.
- The justfile holds only what belongs to a shell: installing tools, building
  the stylesheet, running the spec, a dev server and a REPL.

## Consequences

Tooling composes with what is already loaded, and can be fixed while it runs.
Automation from outside the REPL goes through the admin API, not through a CLI
that would have to be built and kept.
