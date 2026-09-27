# The systems are package-inferred

*2026-09-27, restating a decision of 2026-09-20*

## Context

A system that lists its files in its `.asd` keeps a second record of what the
files' packages already say about each other. ningle-fbr, which routes by file
path, also expects each route file to be a package of its own.

## Decision

`koya-core`, `koya-sdk`, `koya-server` and `koya-spec` are
`:package-inferred-system`s: a file under `src/` or `spec/` is a package, and
its `:import-from`s are its dependencies.

## Consequences

A file's dependencies are read at its top, and the layers spec can read them off
ASDF.

A library whose system name differs from its package's needs a
`register-system-packages` line in the `.asd`.
