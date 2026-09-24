# The server is layered, and each layer depends only on the ones inside it

*2026-09-25*

## Context

`features/` was meant to hold what koya does apart from how it is asked for,
but the line did not hold:

- The content service and the media store raised errors carrying an HTTP
  status (`fail-api 404 …`), and read who was calling from ningle's request.
- The bulk actions and the library caught `api-error`.
- The form reader took ningle's params.
- The presenter read `KOYA_BASE_URL`.

`lib/` held the HTTP plumbing next to logic:

- `query` read the delivery API's parameters and also wrote their SQL.
- `auth` checked keys and also held the Lack guards.
- `timezone` and `totp` read the settings table themselves.

`db/` held more than storage. The content, media, revision and deploy structs
and a content's status rules lived there. So did the check for whether a
space name was acceptable.

Twenty-four pages, components and API routes called `db/` directly. So the
delivery API's preview rule and the schema deploy's destructive-change check
lived in route files.

## Decision

`src/server/` has four layers. Each depends only on the layers inside it:

- `domain/`: what koya is made of. This is the content, media, revision, deploy
  and webhook delivery structs, and a content's status, slug, defaults and
  label. It also holds the delivery API's query language, the TOTP algorithm,
  time zone conversions, image sniffing, and the errors koya raises
  (`not-found`, `conflict`, `invalid-input`, `rejected`, `too-large`, each
  with the code the APIs carry). It depends on `koya/core` alone.
- `usecases/`: what koya does. This covers contents (writing, delivering,
  listing, labels, revisions, bulk), media, spaces (their lifecycle and
  archive), schema deploys, keys, webhooks, settings, logging in, and the
  instance itself. It knows neither HTTP nor SQL. Who is making a change is
  `*actor*`, which the entry point binds.
- `usecases/ports/`: what the use cases need from outside. That is the store
  and its transactions, media files, sending a webhook, sessions, and
  configuration. A port is a package that declares functions (`declaim
  ftype`); the use cases call them.
- `infra/`: those functions, defined in the port's own package by importing
  its symbols. `db/` is SQLite, with the migrations and `schema.sql`;
  `media-files` is the disk; `webhook-sender` is dexador; `env` is the
  environment.
- `web/`: the way in from outside. It holds the pages, `ui/` components and
  actions, both APIs, the HTTP plumbing, the auth guards, the admin API's
  presenters and the app. It turns a request into a use case call, and a
  domain error into a status, in one place (`error-status`).

`koya-server/main` is the composition root. It is the only module that
loads `infra/`, and it loads it before `web/`, whose app calls ports when it
is built. The web reaches the ports through the use cases only. Where a use
case has nothing to add to a port, it re-exports the port's function rather
than wrapping it.

The dependency inversion is by package, not by generic function. A use case
calls `(find-content …)` from a ports package, and infra defines
`find-content` in that package. There is one implementation at a time, no
dispatch and no store argument. The tests use the same implementation over
an in-memory SQLite, which is what they did before.

`tests/server/layers.lisp` reads each file's dependencies off ASDF (a file is
a system, and its dependencies are its imports) and fails on any that
reaches outward.

## Consequences

- A page, an API route and a REPL call reach the same use case, and no use
  case says how anything is stored or asked for.
- Adding a table means adding it to a port and defining the port in
  `infra/db/`. Adding a page means calling use cases. The layer test says
  when either has gone around them.
- Two counts are still worked out in `infra/db`, because the SQL is what
  keeps them cheap: whether a content is referenced, and how many contents
  use a media. Both read the current schema's fields, as they did before.
- A port function is undefined until `infra/` is loaded. Anything that loads
  `koya-server` gets it through `main`; a file loaded on its own at the REPL
  does not.
