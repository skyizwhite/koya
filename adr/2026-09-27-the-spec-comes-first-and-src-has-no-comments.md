# The spec comes first, and src has no comments

*2026-09-27*

## Context

`src/` held about 650 lines of comments and about 420 lines of docstrings. Some
said again what the lines below them did. Others carried what the code could
not say: a constraint, a trap, a reason. Both kinds had to change whenever the
code did, and nothing checked that they had. A reader, whether a person or a
model, could not tell a comment that was still true from one that had gone
stale.

What koya does was said in three places: the tests, the comments and `docs/`.
None of them was the one the others followed.

## Decision

- **The spec is the tests, and it is written first.** A change starts as a spec
  that fails. The implementation is written to pass it, and `docs/` is written
  from what it says. The spec depends on neither of them: nothing under the
  spec reads `docs/`.
- **`tests/` is `spec/`, and `koya-tests` is `koya-spec`.** The system, its
  packages (`koya-spec/...`) and the directory are all renamed, and
  `just test` is now `just spec`.
- **`src/` has no comments and no docstrings**, `schema.sql`'s generated
  header included. What the code does is read from the code; what it must keep
  doing is a spec.
- **The one exception is the site's API, the symbols the `koya-sdk` package
  exports.** A site's developer reads their docstrings in their own REPL, with
  `describe`, and has neither this repository's spec nor its source open. The
  package used to re-export all of `koya-core`, `koya-sdk/config` and
  `koya-sdk/client`. Now it names the 44 symbols in `docs/lisp-sdk.md` and
  exports nothing else, so a symbol exported for the server or for a spec gets
  no docstring. The spec imports those from the package that defines them;
  there is no second facade for it.
- **A reason that neither the spec nor the code can carry goes in `adr/`.** An
  example is something that only happens in the saved executable.

The comments that held a constraint became specs:

- a failed media write leaves no row
- a failed import transaction removes the files it wrote
- removing a space takes its rows and its files
- a bulk delete goes past a file that will not leave the disk
- a rolled-back deploy leaves neither a cached schema nor a log entry
- a delivery key never looks like a management key
- the way back from the login page keeps the request line as it was sent
- a failed login does not say which factor was wrong
- field options are written in one order
- an unreadable session is no session, and an unchanged one is not rewritten
- no space's DOM ids are another space's
- a webhook is sent once the write has committed
- an upload is not cut off by htmx's 60-second timeout
- the space name's pattern escapes its hyphen
- a component with nothing to draw draws nothing

The runtime traps that no spec can reach are in
[the saved image's needs](2026-09-27-what-the-saved-image-needs.md).

## Consequences

- To learn what koya does, read `spec/`. To learn how, read `src/`. To learn
  why it is this way and not another, read `adr/`.
- `describe` and the editor show no docstrings for the server's functions, or
  for anything in `koya-core` and `koya-sdk` that is not the site's API.
- `koya-spec/sdk/main` holds the site's API to that list, and requires each
  symbol in it to be documented. A site that used a `koya-core` symbol through
  `koya-sdk:` has to import it from `koya-core` now.
- A port's promise, which its `:documentation` used to state, is now what the
  specs of its callers require.
- `docs/openapi.yaml` still changes with the API, because the TypeScript client
  is generated from it. It follows the spec; nothing checks it against the
  server.
