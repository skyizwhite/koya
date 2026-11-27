# A scope's members start with an underscore

Superseded by adr/archives/2026-11-27-nagi-replaces-nomini.md

*2026-11-21*

## Context

A part of a page that holds state is a Nomini scope made by a factory in
`assets/js/koya.js`
(`adr/2026-11-21-nomini-swaps-what-an-action-answers-and-holds-a-pages-state.md`).
When an element of a scope asks the server with `$get` or `$post`, Nomini sends
the members of the scope whose names are letters only along with the request,
and calls each function among them to get its value.

## Decision

Every member of a scope made in `koya.js` starts with `_`.

## Consequences

- A scope's state and its methods stay the page's: none of them is sent with a
  request, and no method is called to send it.
- What a request sends is only what the element names in its call.
