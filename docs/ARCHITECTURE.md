# Architecture

What koya is made of. The behaviour it exposes is in
[ADMIN-UI.md](ADMIN-UI.md), [API.md](API.md), [SCHEMA.md](SCHEMA.md),
[openapi.yaml](openapi.yaml) and [lisp-sdk.md](lisp-sdk.md); why it is this way
is in [../adr](../adr). Setting up to work on it is in
[CONTRIBUTING.md](../CONTRIBUTING.md).

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
docs/                 ; this, and the documents above
src/
  main.lisp           ; the koya package: config + client re-exported
  config.lisp         ; defmodel / defwebhooks / current-schema
  client.lisp         ; plan / deploy / pull, get-list …, the admin API wrappers
  core/               ; schema, validate, diff, json, case, time, ulid
  server/
    main.lisp         ; the composition root: loads infra/, then web/
    domain/           ; what koya is made of: content, media, revision, deploy,
                      ; webhook-delivery, references, query, errors, image,
                      ; totp, timezone
    usecases/         ; what koya does, knowing neither HTTP nor SQL:
      contents/       ;   write, delivery, listing, labels, revisions, bulk, lookup,
                      ;   references
      media/          ;   library, delivery
      spaces/         ;   lifecycle, archive
      schema/         ;   deploy
      webhooks/       ;   notify, log
      settings/       ;   timezone, two-factor
                      ;   and actor, auth, keys, system at the top
      ports/          ; what the use cases need from outside: store, spaces,
                      ; contents, media, keys, webhooks, settings, sessions, config
    infra/            ; the ports, defined: env, media-files, webhook-sender, and
      db/             ;   connection, migrations, schema.sql, one file per table
    web/              ; the way in: app, middlewares, http, auth, presenters,
                      ; forms, media, paging, display, urls, assets, document
      pages/          ;   the admin UI (ningle-fbr: the directory is the URL), GET only
      ui/             ;   hsx components shared by pages: layout, icon, toast,
                      ;   elements at the top; content/ and media/ below
      api/            ;   the delivery API
      admin-api/      ;   the admin API
tests/                ; mirrors src/
assets/               ; style/ (Tailwind in and out), js/
```

Both `web/pages/` and the two API directories are file-routed: the path of the
file under them is the URL, and `<space>` in a directory name is a path parameter.

A component that more than one page draws is under `web/ui/`. A component that
only one page draws is in that page's file, next to the actions that answer with
it. See `adr/2026-09-25-shared-components-live-in-ui.md`.

### Layers

Each layer depends only on the ones inside it:

```
web  ──▶  usecases  ──▶  domain
            │ calls
            ▼
          ports  ◀── defines ──  infra
```

- `domain/` depends on `koya/core` alone.
- `usecases/` uses `domain/` and its ports. It raises the errors in
  `domain/errors`, which say what went wrong without an HTTP status, and names
  who is making a change from `*actor*` (`usecases/actor`).
- A port is a package of generic functions, each with the lambda list and the
  documentation that are its contract. `infra/` adds the one method each has,
  so a use case calls `find-content` without knowing that SQLite answers it.
  `koya-server/main` is the only module that loads `infra/`, and it refuses to
  load while a port has no method. The web app is built on first use (`app`),
  not when its file loads, so nothing calls a port before infra is there.
- `web/` reads the request, calls use cases, and draws or words the result. It
  turns a domain error into a status in one place (`error-status` in
  `web/http`). The auth guards bind `*actor*`. The web never reaches a port or
  `infra/` directly: where a use case has nothing to add, it re-exports the
  port's function.

What only one page needs to draw -- its URLs, a badge's class, how a value
reads there -- stays in that page's file.

`tests/server/layers.lisp` fails when a file imports from a layer further out.
See `adr/2026-09-25-the-server-is-layered-and-depends-inward.md`.

## Storage

One SQLite database. The table definitions live in
`src/server/infra/db/migrations.lisp` (forward only, applied at startup); **the
current shape is [`src/server/infra/db/schema.sql`](../src/server/infra/db/schema.sql)**,
generated from them by `(koya-server:write-schema-snapshot)` — a test fails when
it is stale.

| Table | Holds |
|---|---|
| `schema_version` | which migrations have run |
| `spaces` | a space, its webhooks and its webhook secret |
| `models` | a deployed model, as the schema document's own JSON |
| `contents` | every model's contents; `published` and `draft` are JSON |
| `content_revisions` | what each write left a content with, kept until the content is deleted |
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
| Templates | hsx; ningle-actions + HTMX for everything done on a page |
| DB | cl-dbi + dbd-sqlite3 + sxql |
| JSON | jzon, with kebab/camel conversion in `core/case` |
| Client | dexador |
| Archives | zippy (a space's export and import) |
| Other | ironclad, local-time, cl-dotenv, Tailwind CSS v4 (standalone) |
| Tests | rove (`koya-tests`) |

The four apps — pages, delivery API, admin API and actions — are separate ningle
apps mounted together, so each decides its own response type. The admin API and
the actions are each guarded where they are mounted (`*admin-auth-middleware*`,
`*actions-auth-middleware*`), so a route added later is covered without checking
for itself; pages check with `with-owner`. The delivery API is mounted behind
`*delivery-cors-middleware*`, which answers any origin; nothing else is.

A page route answers GET and draws a page; everything done on it is an action
(`defaction`), defined beside the page that calls it, or with the `ui/`
component that cannot work without it (the media picker, Log out). The actions middleware lets
through htmx requests only, from the owner's session and this origin, and sends a
request that has lost its session to the login page with `HX-Redirect`. An action
answers the part of the page it changed, under that part's id, and the toast out
of band into the layout's `#toast`; a result on another page is an `HX-Redirect`
with the toast in the session. A path declared with `public-path` (`web/auth`)
needs no session; logging in is the only one. A path declared with
`archive-path` (`web/middlewares`) takes a space archive as its body, set aside
unread; the import is the only one. Searching, filtering, sorting and
paging a list are actions as well, answered with `HX-Replace-Url` so the page's
URL still carries that state for its GET to draw. See
`adr/2026-09-25-pages-answer-get-and-every-change-is-an-action.md` and
`adr/2026-09-25-lists-are-read-in-place-and-the-url-follows.md`.

## Running it

One Docker image plus a volume for the SQLite file and the media directory,
published to `ghcr.io/skyizwhite/koya` by the Image workflow. The Dockerfile builds in one stage and runs in another: the build loads
`koya-server` and saves it with `(koya-server:save-executable)`, and the runtime
image holds that executable, `assets/` and the C libraries it opens — no
Quicklisp, sources or compiler. Migrations apply themselves at startup.

Environment: `KOYA_SECRET`, `KOYA_DB_PATH`, `KOYA_MEDIA_DIR`, `KOYA_BASE_URL`,
`KOYA_PORT` and `KOYA_ENV`. `GET /health` is unauthenticated and touches the database.

Backups are the volume's; a space's Export is the portable copy of one space.
Assets and media are served `immutable` (their URLs carry a version, and a media
id is never reused); everything else is `no-store`.
