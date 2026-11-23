# The web uses ningle directly

*2026-11-23*

## Context

The pages and the two APIs are ningle apps, and ningle-fbr and ningle-actions,
which route them and run the actions, are written against ningle. jingle adds
to ningle a way to start a server, middlewares, HTTP error conditions, route
names, and helpers that set a response's status and headers, and it re-exports
ningle and part of lack. koya starts and composes its apps with clack and
lack-mw, answers its errors itself, and used jingle only for those helpers and
the re-exports. Using jingle also loads its dependencies, among them jonathan,
a second JSON library beside jzon.

## Decision

The web uses ningle and lack without jingle. What it did for koya, setting a
response's status and Content-Type and redirecting, is a few helpers in
`web/lib/http`.

## Consequences

- ningle is a library of the web layers, `web/`, `ui/` and the pages, in
  `spec/server/layers.lisp`, and lack stays `web/`'s alone: a page or a part of
  the UI that needs the request's body reads it through `web/lib/http`.
- Anything else jingle offered (starting a server, a middleware list, HTTP error
  conditions, route names) is written in koya when koya needs it.
