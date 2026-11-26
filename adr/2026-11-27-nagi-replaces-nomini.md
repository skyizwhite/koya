# Nagi replaces Nomini

*2026-11-27*

## Context

The admin UI swapped what an action answers and held a page's state with
Nomini, kept as it was published
(`adr/2026-11-21-nomini-swaps-what-an-action-answers-and-holds-a-pages-state.md`).
Using it showed where it fell short: one `nm-bind` object per element, which
`web/lib/binds` had to build as a string and merge with what else the element
bound; every member of a scope with a name of letters sent along with a request;
an array sent joined with commas; no file sent; a request in flight cancelled by
any other from its scope, a write among them; an answer swapped in pieces, and a
refused one not drawn.

Nagi is a fork of Nomini, made from these, kept apart from it and released on
its own. It binds each property and each event with an attribute of its own
(`n-bind-hidden`, `n-on-click.prevent`), makes a scope with `n-scope`, sends only
what a request is given, sends a form or a file, cancels only a read with a
newer request and never sends the same write twice at once, and reads an answer
whole.

## Decision

- Nagi (`assets/js/nagi.js`) replaces Nomini. It is taken as it is released,
  and is not changed here.
- A part of a page that holds state is a Nagi scope, made by a named factory in
  `assets/js/koya.js` (`n-scope="koya.bulk(this)"`). Its elements say what they
  show with `n-bind-*` and what they do with `n-on-*`; what needs no state but
  has to run on an element is called from its `n-on-init`.
- The page itself is no scope. State is held only where a part of the page
  needs it.
- `web/lib/binds` writes what a handler runs (`submit`, `post`, `follow`, `ask`,
  `upload-picked`), and the markup names the event it runs on. A search form,
  which asks on three events, is `~search-form`.

## Consequences

- An element's markup has one attribute for each thing it binds, so a component
  adds, leaves out or passes on each one alone.
- The other ADRs written for Nomini hold for Nagi as they stand, `nm-*` read as
  `n-*`, until one of them is replaced.
- A list is sent with its name once for each value; the actions still read a
  value as a list joined with commas as well.
- An inner scope reads the names of the scopes around it when it has none of its
  own.
