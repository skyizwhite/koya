# Working on koya

The koya server is written in Common Lisp. This page is for changing it; using
it from a site is in the [README](README.md).

## Setting up

SBCL, [qlot](https://github.com/fukamachi/qlot) and
[just](https://github.com/casey/just), plus the C libraries the dependencies
compile against: SQLite, libev and a C toolchain.

```sh
just install          # the Tailwind binary and the Lisp dependencies
cp .env.example .env  # set KOYA_SECRET; KOYA_PORT and KOYA_BASE_URL must agree
just build            # the stylesheet (just watch rebuilds it on every change)
just dev              # serves on KOYA_PORT (default 3100)
```

Or from a REPL, which is how the rest of the tooling is run too:

```lisp
(ql:quickload :koya-server)
(koya-server:start)                  ; connect the DB, apply migrations, serve on KOYA_PORT
(koya-server:reload)                 ; reload the code and restart
(koya-server:stop)
(koya-server:write-schema-snapshot)  ; after adding a migration
```

Log in at `/login` with `KOYA_SECRET`, make a space, and take a management key
from its **Keys** page. A site's schema reaches it with `koya deploy` from
[koya-ts-sdk](https://github.com/skyizwhite/koya-ts-sdk), or from the
[Common Lisp SDK](docs/lisp-sdk.md) in this repository.

## Tests

```sh
just test
```

`tests/` mirrors `src/sdk/`, and `tests/server/` mirrors `src/server/`. Anything
touching the database uses an in-memory one, and the admin UI and both APIs are
driven through the app rather than by calling handlers.

## Where things are

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — the two systems, the tables, the
  stack, how the image is built.
- [adr/](adr) — one file per design decision, and why.
- [AGENTS.md](AGENTS.md) — the conventions: what goes in an ADR, how comments are
  written, migrations.
- [docs/openapi.yaml](docs/openapi.yaml) — the APIs. koya-ts-sdk is generated
  from it, so a change to an endpoint changes this document in the same commit.

## Forks

The admin UI's footer links to the source code the AGPL asks a server to offer.
The link is the `:homepage` of `koya-server.asd`: a fork points it at its own
repository.
