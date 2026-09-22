# Operational tooling is REPL functions, not commands

*2026-09-20*

## Context

Development here happens in a REPL attached to a running image. Anything offered
as a shell command has to start its own Lisp, load the system and exit.

## Decision

What operators and developers need is a function: `koya-server:start`, `stop`,
`reload`, `write-schema-snapshot`, `totp-setup`; on the site's side,
`koya:plan`, `deploy`, `pull`. The justfile holds what genuinely belongs to the
shell — installing tools, building the stylesheet, running the suite, a dev
server.

Product settings are in the admin UI, not in environment variables or Lisp
calls, so that the owner can change them without a REPL.

## Consequences

Tooling composes with what is already loaded, and can be fixed while it runs.
Automation from outside the REPL goes through the admin API, not through a CLI
that would have to be built and kept.
