# A transaction is a savepoint koya runs itself

*2026-11-21*

## Context

A deploy opens a transaction inside another: the use case opens one, and the
store opens its own to write the schema. cl-dbi makes the inner one a
savepoint, and runs it, its release and its rollback through `do-sql`, whose
SQLite driver then reads the row count through a statement it never frees. So
each deploy left statements on the connection until it closed, as every `exec`
did before it was made to free what it prepares.

Three ways were open: koya runs the transaction itself, a transaction inside
another joins it, or cl-dbi is mended and koya waits for it.

## Decision

- koya runs every transaction itself, through the same `exec` as any statement:
  `SAVEPOINT` when it opens, `RELEASE` when it ends, and `ROLLBACK TO` then
  `RELEASE` when it fails. The outermost savepoint is the transaction; one
  inside another can be undone alone, as before.
- cl-dbi's transactions are not used. Whether a transaction is open is the
  connection's to say (`in-transaction-p`), not cl-dbi's.

## Consequences

- A transaction leaves no statement behind, at any depth.
- koya only runs SQLite, so nothing is lost by running what cl-dbi would have
  run for it.
- A transaction inside another keeps its meaning: an error caught between the
  two undoes only the inner one.
