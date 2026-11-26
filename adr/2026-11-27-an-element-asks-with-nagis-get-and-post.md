# An element asks with Nagi's own $get and $post

*2026-11-27, restating a decision of 2026-10-02*

## Context

A request could be sent by a wrapper of koya's own, written away from the
element that asks, or by Nagi's `$get` and `$post`, written on it. Nagi sends a
form, with its files, when it is handed the form or the event that submits it,
and moves the browser or replaces its URL when an answer's headers say so.

## Decision

- An element asks with `$get` or `$post` in one of its `n-on-*` attributes,
  which `web/lib/binds` writes from the action's URL: a form on submit, a button
  on click, a link as it is followed, a search as the typing stops, a
  placeholder as it comes into view, a file as it is picked.
- A form sends what the browser would: it is handed to `$post` as the event
  that submits it, or as the form itself.
- An upload's form is a scope of its own, so sending a file cancels no read of
  the part of the page around it.
- An answer that sends the browser to another page, or replaces the page's URL,
  says so in Nagi's `n-redirect` or `n-replace-url` header.
- The actions take only what Nagi sends, `n-request: true` among it.

## Consequences

- What an element asks and what comes of it are in the element's markup.
- A read is cancelled by a newer request from the same scope, so a search that
  is overtaken is not drawn; a write is never cancelled, and the same write is
  not sent again while it is in flight.
- An editor with unsaved changes asks before a move the server sends, as it
  asks before any other, unless the move is one the page asked for on purpose:
  the editor says with `n-on-fetchredirect.window` that a move the server sends
  while it is open is its own, even when the element that asked has been drawn
  again since, and Log out says so with `n-on-fetchredirect`.
- A page the browser brings back from its history asks again.
