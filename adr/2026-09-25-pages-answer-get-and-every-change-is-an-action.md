# Pages answer GET, and every change is an action

*2026-09-25*

## Context

HTMX and ningle-actions were loaded for the whole admin UI, but only the media
picker used them. Everything else was a form post to the page's own route,
answered by a redirect and the whole page drawn again, with the result as a
flash in the session. Publishing a content reloaded the editor, its schema and
every reference it offered; deleting a key reloaded the keys page.

## Decision

A route under `pages/` answers GET only: it draws a page. What is done on a page
is an action (`defaction`), defined next to the page that calls it, or under
`actions/` when more than one place needs it (the media picker, the space
import). Logging in is an action too.

Every action is guarded where the actions app is mounted, in this order: an
htmx request (`HX-Request`), or 400; the owner's session, or 401 with an
`HX-Redirect` to the login page and back to the page the request came from
(`HX-Current-URL`); the same origin for anything that writes, or 403. An action
checks only what it is about: that the space or content it names exists.

A path is let through without a session by being declared a public path
(`public-path`, in `lib/auth`) where it is defined. Logging in is the only one:
it is where a session comes from. It still has to be htmx from this origin, so
another site cannot log a browser in. The list is by path rather than by action
so that whatever else guards by session can read the same one.

An action answers the part of the page it changed, drawn again whole under its
id (`#library`, `#editor`, `#contents`...), and the flash goes out of band into
the layout's `#flash`. One that is refused leaves the page alone
(`HX-Reswap: none`) and says why in the flash. One whose result is another page
-- a content just made, one deleted, a space imported -- sends the browser
there with `HX-Redirect`, and the flash waits in the session as before.

What lives in the query string -- search, filters, sort, page, tabs -- stays a
page load: a list as it is being read is still a link.

The space import is an action too. Its body is the zip itself, which the body
limit middleware sets aside before anything reads it; the middleware knows the
action by the path its function returns, which is why that action is under
`actions/`, loaded before any page.

Dialogs open and close by HTML (`commandfor`, `closedby`), and the JavaScript
that remains (Quill, the reference chips, the selection bar, the QR code) binds
with `htmx.onLoad`, so a part swapped in works as the page it replaced did.

## Consequences

The admin UI needs JavaScript. A form carries `hx-post` and no `method` or
`action`, and a page has nothing to post to.

An action's URL is made by its function (`(delete-key :space ...)`), so a view
and the handler it calls cannot drift apart, and tests call the function too.

Moving between pages is still plain navigation, so the back button and a
bookmark keep working, and there is no client state to keep in step with the
URL beyond `HX-Replace-Url` after a restore is saved.
