# Routes do not import one another

*2026-09-27*

## Context

The pages and the two APIs are file-routed: ningle-fbr loads each file under
`web/pages/`, `web/api/` and `web/admin-api/` by its path. Three pages had
come to import URL functions from other pages: the space page took
`webhook-log-url` from the webhook log and `deploys-url` from the deploy log,
the model list and the editor took `webhook-log-url` as well, and the editor
took `history-url` from its history page. Loading one page loaded another, and
a page's package was part of what the others were built on.

`tests/server/layers.lisp` put all of `web/` in one layer, so nothing checked
this, nor that `ui/` never used a page.

## Decision

- **A URL that more than one page links to is in `web/urls`.** `history-url`,
  `deploys-url` and `webhook-log-url` moved there. A URL that only its own page
  uses, like the history page's `restore-url`, stays in that page's file and is
  not exported.
- **Each router is a layer of its own in `layers.lisp`, and isolated.**
  - `:web` is the rest of `web/`: app, http, auth, presenters, urls and the like.
  - `:ui` is `web/ui/`, and may use `:web`.
  - `:pages`, `:api` and `:admin-api` are the three routers. `:pages` may use
    `:ui` and `:web`; the two APIs, which draw nothing, `:web` only.

  Nothing may use a router, and okite's `(:isolated :pages :api :admin-api)`
  keeps a route from using another route of its own router.

## Consequences

- A page can be deleted or moved without touching another page.
- A route using another route, `ui/` using a page, or `web/app` using `ui/`
  fails the layers test.
