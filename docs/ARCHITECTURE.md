# Architecture

What koya is made of. The behaviour it exposes is in
[ADMIN-UI.md](ADMIN-UI.md), [CLIENT.md](CLIENT.md), [SCHEMA.md](SCHEMA.md) and
[openapi.yaml](openapi.yaml); why it is this way is in [../adr](../adr).

## Two systems, one repository

| System | Holds |
|---|---|
| `koya` | the schema DSL, the HTTP client, and `koya/core` |
| `koya-server` | the admin UI, the delivery API, the admin API and the media store |

`koya/core` — the schema, its validation, the diff between two of them, JSON and
name conversion, ULIDs — is shared, which is why one repository holds both. A
site depends on `koya` alone; `qlot` pulls it by git.

```
koya.asd  koya-server.asd  koya-tests.asd  qlfile  justfile  Dockerfile
adr/                  ; one file per design decision
docs/                 ; this, and the four documents above
src/
  main.lisp           ; the koya package: config + client re-exported
  config.lisp         ; defmodel / defwebhooks / current-schema
  client.lisp         ; plan / deploy / pull, get-list …, the admin API wrappers
  core/               ; schema, validate, diff, json, case, time, ulid
  server/
    app.lisp  main.lisp  document.lisp
    pages/            ; the admin UI (ningle-fbr: the directory is the URL)
    components/       ; hsx components shared by pages
    api/              ; the delivery API
    admin-api/        ; the admin API
    db/               ; connection, migrations, and one file per table
    lib/              ; env, auth, http, query, presenter, content-service,
                      ; forms, page, timezone, totp, media-store, webhook
tests/                ; mirrors src/
assets/               ; style/ (Tailwind in and out), js/
```

Both `pages/` and the two API directories are file-routed: the path of the file
is the URL, and `<space>` in a directory name is a path parameter.

## Storage

One SQLite database. The table definitions live in `src/server/db/migrations.lisp`
(forward only, applied at startup); **the current shape is
[`src/server/db/schema.sql`](../src/server/db/schema.sql)**, generated from them
by `(koya-server:write-schema-snapshot)` — a test fails when it is stale.

| Table | Holds |
|---|---|
| `schema_version` | which migrations have run |
| `spaces` | a space, its webhooks and its webhook secret |
| `models` | a deployed model, as the schema document's own JSON |
| `contents` | every model's contents; `published` and `draft` are JSON |
| `schema_deploys` | what each deploy changed |
| `delivery_keys` `management_keys` | keys, as SHA-256 |
| `media` | an uploaded file's metadata; the file itself is on disk |
| `webhook_deliveries` | what each webhook call answered |
| `sessions` `settings` | the admin UI's own state |

Ids are ULIDs. A model's fields are not columns: they are keys in the JSON, so
changing a schema never changes a table.

## Stack

SBCL with package-inferred systems — a file under `src/` is a package — and
`qlot` for dependencies.

| Layer | |
|---|---|
| HTTP | Clack / Lack; Hunchentoot in development, Woo in production |
| Router | jingle (a ningle extension) + ningle-fbr |
| Templates | hsx, with ningle-actions + HTMX for the media picker |
| DB | cl-dbi + dbd-sqlite3 + sxql |
| JSON | jzon, with kebab/camel conversion in `core/case` |
| Client | dexador |
| Other | ironclad, local-time, cl-dotenv, Tailwind CSS v4 (standalone) |
| Tests | rove (`koya-tests`) |

The four apps — pages, delivery API, admin API and actions — are separate ningle
apps mounted together, so each decides its own response type.

## Running it

One Docker image plus a volume for the SQLite file and the media directory,
deployed on Coolify. Migrations apply themselves at startup.

Environment: `KOYA_SECRET`, `KOYA_DB_PATH`, `KOYA_MEDIA_DIR`, `KOYA_BASE_URL`,
`KOYA_PORT`, `KOYA_ENV`, and `KOYA_TOTP_SECRET` to set two-factor login from
outside the UI. `GET /health` is unauthenticated and touches the database.

Backups are the volume's. Assets and media are served `immutable` (their URLs
carry a version, and a media id is never reused); everything else is `no-store`.
