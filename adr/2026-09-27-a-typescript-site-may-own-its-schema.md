# A TypeScript site may own its schema

*2026-09-27, restating a decision of 2026-09-23*

## Context

`plan` and `deploy` began as the Lisp library's alone. A site written in
TypeScript would otherwise have to keep its schema in Lisp.

## Decision

A TypeScript project may declare and deploy its schema. `koya-ts-sdk` has
`koya plan`, `deploy`, `pull` and `types`, as a CLI run from npm scripts: on that
side there is no REPL to keep them in.

## Consequences

A deploy from TypeScript is as safe as one from Lisp, since the server computes
the diff and refuses destructive changes without `force`.
