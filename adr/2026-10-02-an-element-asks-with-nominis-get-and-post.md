# An element asks with Nomini's own $get and $post

*2026-10-02, restating a decision of 2026-10-02*

## Context

With HTMX gone, a request could be sent by a wrapper of koya's own, written
away from the element that asks, or by Nomini's `$get` and `$post`, written on
it. Nomini's `$fetch` sends an object as a query string and reads no headers,
and it cannot send a file.

## Decision

- An element asks with `$get` or `$post` in its own `nm-bind`, which
  `web/lib/binds` writes from the action's URL: a form on submit, a button on
  click, a link as it is followed, a search as the typing stops, a placeholder
  as it comes into view. `koya.form` makes a form's fields into what they send.
- An answer that sends the browser to another page, or replaces the page's URL,
  is an element swapped into the document's `#location`, which does it as it is
  drawn.
- A file is sent by an upload's own fetch, and its answer is handed to Nomini as
  a `data:` URL through the scope's `$fetch`.
- The actions take only what Nomini sends, `nm-request: true` among it.

## Consequences

- What an element asks and what comes of it are in the element's markup.
- A request cancels the one in flight from the same scope, as Nomini does: a
  search that is overtaken is not drawn.
- A Content-Security-Policy, if one is added, has to let the page fetch `data:`.
