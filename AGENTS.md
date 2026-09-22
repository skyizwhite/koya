# Working on koya

koya is a small self-hosted headless CMS in Common Lisp: a server (admin UI,
delivery API, admin API, media) and a library a site uses to declare its schema
and read its content. Start with [README.md](README.md) and
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Design decisions go in `adr/`

One file per decision, `adr/<date>-<title>.md`, in English, with Context,
Decision and Consequences. Record the ones a reader would otherwise ask "why is
it like this?" about — not every edit.

**An ADR is not edited.** When a decision is replaced, write a new one and add
`Superseded by adr/<file>` under the old one's title. The history is the point.

What is true *now* belongs in `docs/`, which is edited freely:
ARCHITECTURE.md for the shape of the system, ADMIN-UI.md, CLIENT.md, SCHEMA.md
and openapi.yaml for what it does.

## Tests

```sh
just test
```

`tests/` mirrors `src/`. Anything touching the database uses an in-memory one,
and the admin UI and both APIs are driven through the app rather than by calling
handlers.

## Conventions

- **Tooling is REPL functions, not commands.** `koya-server:start` / `stop` /
  `reload` / `write-schema-snapshot`, and `koya:plan` / `deploy` / `pull` on the
  site's side. The justfile holds only what belongs to a shell.
- **Product settings live in the admin UI**, not in environment variables.
- Migrations are forward-only and apply themselves at startup. After adding one,
  run `(koya-server:write-schema-snapshot)` — a test fails while `schema.sql` is
  stale.
- Comments carry what the code cannot: a constraint, a trap, a reason. Not a
  restatement of the lines below them, and not how the code came to be — that is
  what git and `adr/` are for.
