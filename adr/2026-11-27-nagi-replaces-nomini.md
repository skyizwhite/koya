# Nagi replaces Nomini

*2026-11-27*

## Context

The admin UI swapped what an action answers and held a page's state with
Nomini, kept as it was published
(`adr/archives/2026-11-21-nomini-swaps-what-an-action-answers-and-holds-a-pages-state.md`).
Using it showed where it fell short, and koya worked around each:

- one `nm-bind` object per element, which `web/lib/binds` built as a string and
  merged with what else the element bound;
- binds written after an await, so an event sent after a change had to wait;
- every member of a scope with a name of letters sent with a request, so each
  member's name started with `_`;
- an array sent joined with commas, and no form or file sent, so `koya.form`
  made a form into an object and an upload made its own fetch;
- an answer swapped in pieces, a refused one not drawn, and no header read, so
  `koya.js` wrapped `window.fetch`, and a move or a new URL was an element
  swapped into `#location`;
- a write cancelled by any request after it from its scope.

Nagi is a fork of Nomini, made from these, kept apart from it and released on
its own. It binds each property and each event with an attribute of its own,
writes a bind as soon as what it reads changes, sends only what a request is
given and sends a form with its files, reads an answer whole, swaps a refused
one, moves the browser or replaces its URL as an answer's headers say, and
cancels only a read with a newer request.

## Decision

- Nagi (`assets/js/nagi.js`) replaces Nomini. It is taken as it is released,
  and is not changed here.
- A part of a page that holds state is a Nagi scope, made by a named factory in
  `assets/js/koya.js` (`n-scope="koya.bulk(this)"`). Its elements say what they
  show with `n-bind-*` and what they do with `n-on-*`; what needs no state but
  has to run on an element is called from its `n-on-init`.
- A scope's members are named for what they are, with no mark of their own.
- The page itself is no scope. State is held only where a part of the page
  needs it.
- `web/lib/binds` writes what a handler runs (`submit`, `post`, `follow`, `ask`,
  `upload-picked`), and the markup names the event it runs on. A search form,
  which asks on three events, is `~search-form`.

## Consequences

- An element's markup has one attribute for each thing it binds, so a component
  adds, leaves out or passes on each one alone.
- What koya did around Nomini is gone: `koya.form`, the upload's own fetch, the
  wrapper of `window.fetch` and `#location`.
- A change made by a scope is in the page by the time the next line runs, so an
  event about it is sent at once.
- An inner scope reads the names of the scopes around it that it does not have
  itself, and a scope's element gives it its `data-*` as members.
- The ADRs written for Nomini that this one does not replace hold for Nagi,
  `nm-*` read as `n-*`.
