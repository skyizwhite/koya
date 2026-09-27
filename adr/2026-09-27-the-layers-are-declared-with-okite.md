# The server's layers are declared with okite

*2026-09-27, restating a decision of 2026-09-26*

## Context

The layers of `adr/2026-09-27-the-server-is-layered-and-depends-inward.md` are
kept by a spec that reads every file's dependencies. Code that did this knew
nothing about koya but the names in it, and would be one more thing to maintain
and test here.

## Decision

The check is [okite](https://github.com/skyizwhite/okite), a separate MIT
library pulled with qlot. `spec/server/layers.lisp` declares with
`define-layers` the layers, what each may use, which routers are isolated, which
layers each library belongs to and what is forbidden, such as `koya-sdk`, and
fails on any of `layer-violations`.

## Consequences

The rules read as a declaration rather than as the code that applies them. What
okite checks is tested in okite, and koya's spec holds only koya's rules.
