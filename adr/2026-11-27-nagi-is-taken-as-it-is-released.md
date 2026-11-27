# Nagi is taken as it is released

*2026-11-27, restating a decision of 2026-11-27*

## Context

The admin UI swaps what an action answers and holds a page's state with a small
library in the browser. Nomini, used first, fell short in use. It took one
`nm-bind` object for all an element binds, and wrote binds after an await. It
sent every member of a scope with a name of letters with a request, sent an
array joined with commas, and sent no form or file. It swapped an answer in
pieces and drew no refused one, read no header, and cancelled a write with any
request after it from its scope.

Nagi is a fork of Nomini, made from these and released on its own. It binds each
property and each event with an attribute of its own, and writes a bind as soon
as what it reads changes. It sends only what a request is given, and sends a
form with its files. It reads an answer whole and swaps a refused one, moves the
browser or replaces its URL as an answer's headers say, and cancels only a read
with a newer request.

## Decision

Nagi (`assets/js/nagi.js`) is the admin UI's library in the browser. It is
taken as it is released, and is not changed here.

## Consequences

- An element's markup has one attribute for each thing it binds, so a component
  adds, leaves out or passes on each one alone.
- A change made by a scope is in the page by the time the next line runs, so an
  event about it is sent at once.
- What Nagi does not do is done in `assets/js/koya.js`, or asked of Nagi in a
  release of its own.
- The ADRs written for Nomini that no later one replaces hold for Nagi, `nm-*`
  read as `n-*`, `nomini.js` as `nagi.js`, and an `nm-bind` as the `n-bind-*` and
  `n-on-*` it held.
