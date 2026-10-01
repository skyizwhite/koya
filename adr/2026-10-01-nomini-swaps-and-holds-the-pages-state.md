# Nomini swaps what an action answers and holds a page's state

*2026-10-01*

## Context

The admin UI swapped fragments with HTMX, and everything a page held in the
browser -- a selection, whether Save draft has anything to save, the phrase
typed to confirm, the chips of a many-reference field, the file a media field
holds -- was hand-written JavaScript that found its elements by `data-*`
markers and bound them again after every swap. Two ways of making a page work
lived side by side, and the second grew with every screen.

Nomini does both in one small file: it swaps the elements of an answer by id,
and gives a part of the page a reactive scope (`nm-data`) that its elements read
and change (`nm-bind`), bound again whenever something is swapped in.

## Decision

- Nomini (`assets/js/nomini.js`) replaces HTMX. It is kept as it is published,
  and is not changed.
- A part of a page that holds state is a Nomini scope, made by a named factory
  in `assets/js/koya.js` (`nm-data="...koya.bulk(this)"`). Its elements say what
  they show and do with `nm-bind`; what needs no state but has to run on an
  element (Quill, the QR code, fitting a frame) is called from its `oninit`.
- What the server draws for a scope is all of it: a list of chips is drawn
  whole and the state shows or hides each one, since a scope cannot make
  elements.

## Consequences

- One way of making a page work, and the JavaScript is the factories, named
  from the markup, rather than code that goes looking for the markup.
- Nomini's state is shallow and its binds write after an await: a list changes
  by being set again, and an event sent after a change waits for the binds.
- A scope does not see the one around it; scopes that work together hold each
  other, as the media field and the picker do.
- Nomini does not send what HTMX sent, so a request goes through a wrapper of
  koya's own (`adr/2026-10-01-requests-go-through-a-wrapper-around-nomini.md`).
