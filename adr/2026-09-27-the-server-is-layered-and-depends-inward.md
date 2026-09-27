# The server is layered, and each layer depends only on the ones inside it

*2026-09-27, restating a decision of 2026-09-25*

## Context

What koya does had spread into how it is asked for and how it is stored. Use
cases raised errors that carried an HTTP status and read ningle's request. One
module both parsed the delivery API's query and wrote its SQL. Route files held
rules such as the preview rule and the destructive-change check.

## Decision

`src/server/` has layers, and each one depends only on the layers inside it:

- `domain/` is what koya is made of: the content, media, revision, deploy, key
  and webhook delivery structs, the delivery API's query language, references,
  TOTP, time zones, image sniffing and the errors. It depends on `koya-core`
  alone.
- `usecases/` is what koya does. It knows neither HTTP nor SQL. Who makes a
  change is `*actor*`, which the entry point binds.
- `usecases/ports/` is what the use cases need from outside: the store and its
  transactions, media files, archives, sending a webhook, sessions and
  configuration.
- `infra/` implements the ports: `db/` with SQLite, `media-files`, `archives`,
  `webhook-sender` and `env`.
- `web/` is the way in: the pages, `ui/`, both APIs, the HTTP plumbing, the
  guards and the presenters.

## Consequences

- A page, an API route and a REPL call reach the same use case, and no use case
  says how anything is stored or asked for.
- Adding a table means adding it to a port and implementing it in `infra/db/`.
  Adding a page means calling use cases.
- `spec/server/layers.lisp` fails on a dependency that reaches outward.
