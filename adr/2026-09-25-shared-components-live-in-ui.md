# Shared components live in ui/, a page's own stay with it

Superseded by adr/2026-09-25-a-space-has-no-size-limit-and-moves-in-pieces.md (how the import action takes its body)

*2026-09-25*

## Context

The hsx components more than one page draws were in four places.
`lib/page.lisp` held the layout, the icons, the toast and the small pieces,
next to helpers that draw nothing (`with-owner`, `param`, the URLs, how a time
or a caller reads). `document.lisp` sat at the top of the server,
`components/` held the field controls and the media grid, and the media
picker, a dialog with the two actions that fill it, was under `actions/`.
Finding where something on the screen is drawn meant knowing which of the four
it had ended up in. `lib/page` also shared its name with `pages/` while being
neither a page nor the whole of what pages use.

`actions/` held the space import as well. Only the spaces page calls it; it was
kept apart because the body limit middleware knew it by the path its function
returned, and the middleware is loaded before any page is.

## Decision

Every component shared by pages is under `src/server/ui/`. The ones any page may
draw are at its top: `layout` (the header, the crumbs, the footer and Log out),
`icon`, `toast` and `elements` (errors, the empty state, the status badge). The
ones that belong to one part of koya are under a directory named for it:
`ui/content/` for the editor's field controls, `ui/media/` for the grid and the
picker. `document.lisp` stays beside `app.lisp`: it is what `app` wraps every
page in, not something a page draws.

A component under `ui/` may carry the actions it cannot work without, as the
picker does and the layout's Log out does. `ui/` depends on `lib/` and `db/`,
never on `pages/`.

A component used by one page stays in that page's file. It calls the page's
actions for their URLs and those actions answer with it, so moving it elsewhere
would make two packages that each need the other.

`lib/page` is gone; what it held went to the package it is about:

| What | Now in |
|---|---|
| `with-owner`, `local-path-p` | `lib/auth`, with the other guards |
| `param`, `redirect-to` | `lib/http` (`param` was `query-param` there already) |
| `set-toast`, `take-toast` | `ui/toast`, with the toast they carry |
| `set-title` | `document`, which draws the title |
| `short-time`, `caller-name` | `lib/display` |
| `content-label` | `lib/display`; since then `features/contents/labels` |
| `space-url`, `model-url`, `content-url`, `expand-url-template` | `lib/urls` |

The import action is on the spaces page. It declares its path with
`archive-path` from `middlewares`, where it is defined, as a public path is
declared with `public-path`; the middleware looks the path up when a request
comes, by which time the pages are loaded. `actions/` is gone.

## Consequences

What a page draws comes from `ui/…` and what it does from `lib/…`, and its
imports say which is which.

A component that a second page starts to use moves from that page into `ui/`.

What takes a space archive as its body is found by looking for `archive-path`,
as what needs no session is found by looking for `public-path`.
