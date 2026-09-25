# Ports are generic functions, and the server checks they are all implemented when it loads

Superseded by adr/2026-09-25-use-cases-hand-over-data-and-the-web-makes-json.md (who implements a port)

*2026-09-25*

## Context

`adr/2026-09-25-the-server-is-layered-and-depends-inward.md` made a port a
package of functions declared with `declaim ftype`, which infra then defined
with `defun`. This left three weaknesses:

- **A port said nothing about its functions.** It gave no lambda list and no
  documentation. What a function took, and what it promised, was only in
  infra.
- **A missing implementation was found late.** The FTYPE declamation silenced
  the undefined-function warning. So a function added to a port and never
  defined in infra went unnoticed until a request called it.
- **The load order mattered.** `web/app` built the app when its file loaded,
  and building it calls ports. So `koya-server/main` had to load infra before
  the web, and a reordered import broke loading.

## Decision

- **A port function is a `defgeneric`.** Its lambda list and documentation are
  the contract. Infra implements it with a `defmethod`, which CLOS checks
  against that lambda list when infra loads.
- **Methods are not specialized.** There is still one implementation, and most
  arguments are strings, some of them NIL, so there is nothing to dispatch
  on. The generic function is there for the contract and the checks, not for
  dispatch. Swapping implementations would take a store object as the first
  argument, which the tests, on an in-memory SQLite, do not need.
- **`koya-server/main` refuses to load while a port has no method.** When it
  loads, infra has too, so this is the earliest a missing implementation can
  be seen. `unimplemented-ports` lists them. Loading stops at the REPL, in the
  image build and in `just test` alike.
- **The web app is built on first use.** `(app)` builds it when `start`, `main`
  or a test first asks for it, not when `web/app` loads. Nothing calls a port
  while the code is loading. `reload` clears it so that it is built again from
  the new code.

## Consequences

- Reading a port tells what each function takes and promises; the methods in
  infra carry only how.
- A use case called without infra loaded fails with "no applicable method" for
  the function it called, which names the port. It is still a runtime error;
  what catches a missing implementation early is the check at load.
