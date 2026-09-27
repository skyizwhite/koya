# Product settings live in the admin UI

*2026-09-27, restating a decision of 2026-09-20*

## Context

A setting in an environment variable or behind a Lisp call can be changed only
by whoever runs the server, and only by restarting it or reaching its REPL. The
published image has no REPL.

## Decision

What the owner chooses about koya, such as two-factor login and the time zone,
is set in the admin UI and kept in the database. The environment holds only what
the process needs before it can open the database: where the data is, the port,
the public URL and the owner secret.

## Consequences

The owner changes a setting without a REPL or a restart, and a backup of the
data directory carries the settings with it.
