# An element asks the server with Nomini's own $get and $post

Superseded by adr/2026-10-02-an-element-asks-with-nominis-get-and-post.md
Superseded by adr/2026-10-02-nomini-is-handed-each-answer-whole-and-drawable.md

*2026-10-02*

## Context

With HTMX gone, a request could be sent by a wrapper of koya's own, which read
the answer's headers and status and handed the body to Nomini; or by Nomini's
`$get` and `$post`, written on the element that asks. The wrapper put what an
element does in a file away from it, and needed a scope of its own to reach
Nomini's swap.

Nomini's `$fetch` sends an object as a query string, reads no headers, and
draws nothing of an answer that is not ok: it reports it with `fetcherr`,
carrying the body in the error's message. It cannot send a file.

## Decision

- An element asks with `$get` or `$post` in its own `nm-bind`, which
  `web/lib/binds` writes from the action's URL: a form on submit, a button on
  click, a link as it is followed, a search as the typing stops, a placeholder
  as it comes into view. `koya.form` makes a form's fields into what they send.
- An action answers what it answered before, with its status. A refused answer
  is drawn like any other: the element's `fetcherr` hands its body back to the
  scope's `$fetch` as a `data:` URL, and Nomini swaps it in. An answer with
  nothing to draw is said in the toast.
- An answer that sends the browser to another page, or replaces the page's URL,
  is an element swapped into the document's `#location`, which does it as it is
  drawn.
- A file is sent by an upload's own fetch, and its answer drawn as a refusal is.
- Nomini swaps what it has read of an answer whenever 20 ms pass without more,
  so an answer that arrives in pieces would be swapped in part. `koya.js` wraps
  `window.fetch` so that a request Nomini makes (`nm-request`) is read whole
  before Nomini sees it.
- The actions take only what Nomini sends, `nm-request: true` among it.

## Consequences

- What an element asks and what comes of it are in the element's markup.
- koya depends on three things Nomini does without promising them: the message
  of the error for an answer that is not ok, how `$fetch` reads a `data:` URL,
  and that it reads an answer through `window.fetch`. A new Nomini is checked
  against all three before it is taken.
- A request cancels the one in flight from the same scope, as Nomini does: a
  search that is overtaken is not drawn.
- A Content-Security-Policy, if one is added, has to let the page fetch `data:`.
