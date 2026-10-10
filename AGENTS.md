# Working on koya

koya is a small self-hosted headless CMS in Common Lisp: a server (admin UI,
delivery API, admin API, media) and a library a site uses to declare its schema
and read its content. Start with [README.md](README.md) and
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Design decisions go in `adr/`

One decision per file, `adr/<date>-<title>.md`, in English, with Context,
Decision and Consequences. Record the ones a reader would otherwise ask "why is
it like this?" about — not every edit.

**An ADR records a design decision, not a work log.** A decision is a choice
among alternatives whose reason someone could later ask for. A rename, a file or
package moved, a table of what went where, or a trick that works around a
library is a change, not a decision: git holds it, and a constraint worth
keeping is a spec. Write what is decided, not how the code got there.

**An ADR is not edited once it is on `master`, and it is replaced whole.** An
ADR that only the branch being worked on has added is still a draft: edit it,
rename it or delete it as the work goes. When a decision on `master` changes,
write the new one, and write again, one ADR each, whatever of the old ADR still
holds. Then add `Superseded by adr/<file>` lines under the old one's title and
move it to `adr/archives/`. `.ignore` keeps `adr/archives/` out of searches: do
not read it unless asked.

What is true *now* belongs in `docs/`, which is written from the spec and
edited freely:
ARCHITECTURE.md for the shape of the system, ADMIN-UI.md, API.md, SCHEMA.md,
lisp-sdk.md and openapi.yaml for what it does. README.md is written for the
people who use koya from a TypeScript site and says nothing about Lisp; setting
up to work on koya is in CONTRIBUTING.md.

## The spec comes first

```sh
just spec
```

The spec is the tests in `spec/` (`koya-spec`), and a change starts as a spec
that fails. The implementation is written to pass it, and `docs/` follows what
it says; nothing in the spec reads `docs/`.

`spec/` mirrors `src/`: `core/`, `sdk/` and `server/`. Anything touching the
database uses an in-memory one, and the admin UI and both APIs are driven through
the app rather than by calling handlers.

## Conventions

- **Tooling is REPL functions, not commands.** `koya-server:start` / `stop` /
  `reload` / `write-schema-snapshot`, and `koya-sdk:plan` / `deploy` / `pull` on
  the site's side. The justfile holds only what belongs to a shell.
- **Product settings live in the admin UI**, not in environment variables.
- Migrations are forward-only and apply themselves at startup. After adding one,
  run `(koya-server:write-schema-snapshot)` — a test fails while `schema.sql` is
  stale.
- **The server depends inward**: `domain/` ← `usecases/` ← `infra/`, `web/`.
  A store keeps what a use case decided and decides nothing; a use case returns
  data and `web/` makes the JSON. `spec/server/layers.lisp` checks the
  direction.
- **Guards are where things are mounted**, deny by default. A page or an action
  does nothing about who is asking; what is open says so with `public-path`.
- **A page answers GET; every change is a `defaction`.**
- **`docs/openapi.yaml` changes with the API** — the TypeScript client is
  generated from it.
- **`koya-core` and `koya-sdk` are MIT, `koya-server` is AGPL.** Moving a file
  across that line is a licensing change (see the ADR for which files). The
  server and the SDK share `koya-core` and do not use each other.
- **`src/`, `spec/` and `assets/js/koya.js` have no comments, and `src/` and
  `spec/` no docstrings.** What the code must keep doing is a spec; why it is
  this way is an ADR. In `spec/`, what a check
  means goes in its `testing` or `ok` description. The one exception is the
  site's API, the symbols the `koya-sdk` package exports: they keep their
  docstrings for a site's developer at the REPL. That package names each of
  them, and a symbol exported only for the server or a spec stays in its own
  package.
