# Nagi replaces Nomini

Superseded by adr/2026-11-27-nagi-is-taken-as-it-is-released.md
Superseded by adr/2026-11-27-a-part-of-a-page-that-holds-state-is-a-scope.md
Superseded by adr/2026-11-27-a-scopes-members-carry-no-mark.md
Superseded by adr/2026-11-27-the-page-itself-is-no-scope.md
Superseded by adr/2026-11-27-what-the-server-writes-for-a-scope-is-a-data-attribute.md
Superseded by adr/2026-11-27-binds-writes-what-a-handler-runs.md

*2026-11-27*

## Context

The admin UI swapped what an action answers and held a page's state with
Nomini, kept as it was published
(`adr/archives/2026-11-21-nomini-swaps-what-an-action-answers-and-holds-a-pages-state.md`).
Using it showed where it fell short: one `nm-bind` object for all an element
binds, binds written after an await, every member of a scope with a name of
letters sent with a request, an array sent joined with commas, no form or file
sent, an answer swapped in pieces and a refused one not drawn, no header read,
and a write cancelled by any request after it from its scope.

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
- A change made by a scope is in the page by the time the next line runs, so an
  event about it is sent at once.
- An inner scope reads the names of the scopes around it that it does not have
  itself, and a scope's element gives it its `data-*` as members.
- The ADRs written for Nomini that this one does not replace hold for Nagi,
  `nm-*` read as `n-*`.
