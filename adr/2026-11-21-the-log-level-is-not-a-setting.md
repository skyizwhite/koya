# The log level is not a setting

*2026-11-21*

## Context

A log level could be a setting: in the admin UI, where koya's product settings
are, or in an environment variable. What koya logs is what an owner looks for
afterwards: errors, refusals and the few events that change a space.

## Decision

The log has no level setting. Everything at info and above is written. The
level can be changed at the REPL through verbose.

## Consequences

- An owner cannot quiet the log from the admin UI or the environment.
- A debug line added later is not seen in production.
