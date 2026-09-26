# Layers and ports are checked with okite

*2026-09-26*

## Context

Two checks kept the server's shape. `tests/server/layers.lisp` read every
file's dependencies off ASDF and compared them with the layers of
`adr/2026-09-25-the-server-is-layered-and-depends-inward.md`, and with the
layers each library belongs to. `unimplemented-ports` in `usecases/ports/main`
listed the generic functions of the ports no method implemented, which
`koya-server/main` turns into an error as it loads
(`adr/2026-09-25-ports-are-generic-functions-checked-when-the-server-loads.md`).

Neither knew anything about koya but the names in it, and both were code to
maintain and test here.

## Decision

Both move to [okite](https://github.com/skyizwhite/okite), a separate MIT
library pulled with qlot:

- `tests/server/layers.lisp` declares the layers, what each may use, the
  libraries' layers and that `koya-sdk` is forbidden with `define-layers`, and
  fails on any of `layer-violations`.
- `koya-server/main` calls `ensure-implemented` on `+ports+`, which stays in
  `usecases/ports/main` as the list of the ports.

## Consequences

The rules read as a declaration rather than as the code that applied them.
What okite checks is tested in okite; koya's tests hold only koya's rules.

okite is a dependency of the server at run time as well as in the tests, since
`main` checks the ports as it loads.
