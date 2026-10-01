# Pages answer GET, and every change is an action

*2026-10-01, restating a decision of 2026-09-25*

## Context

Most of the admin UI was forms posted to the page's own route and answered with
a redirect, so every change drew the whole page again. Publishing a content
reloaded the editor, its schema and every reference it offered.

## Decision

- A route under `pages/` answers GET only: it draws a page.
- Whatever is done on a page is an action, a `defaction`. It is defined next to
  the page that calls it, or in `ui/` next to the component that cannot work
  without it. Logging in is an action too.
- An action's URL is made by its function, as in `(delete-key :space ...)`.

## Consequences

- A form carries its action in `data-post` (or `data-get`) and no `method` or
  `action` of its own, and a page has nothing to post to. The admin UI needs
  JavaScript.
- A view and the handler it calls cannot drift apart, and the specs call the
  same function.
- Moving between pages is still plain navigation.
