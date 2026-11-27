# Nagi swaps answers and holds a page's state

*2026-11-27, restating a decision of 2026-11-27 for Nagi 0.4*

## Context

The admin UI swaps what an action answers and holds a page's state with Nagi,
which replaced Nomini (`adr/archives/2026-11-27-nagi-replaces-nomini.md`). Nagi
0.4, its first release, settled what an attribute's code sees: `this` is the
scope in every attribute, as it is in a scope's methods, and `$el` is the
element the attribute is written on. A scope's names are only what `n-scope`,
`n-let-*` and `n-form` give it; its element's `data-*` are no longer among them.

## Decision

- Nagi (`assets/js/nagi.js`) is taken as it is released, and is not changed
  here.
- A part of a page that holds state is a Nagi scope, made by a named factory in
  `assets/js/koya.js`, which is handed the scope's element as `$el`
  (`n-scope="koya.bulk($el)"`). Its elements say what they show with
  `n-bind-*` and what they do with `n-on-*`, and hand themselves to what they
  call as `$el`; what needs no state but has to run on an element is called
  from its `n-on-init`.
- A scope's members are named for what they are, with no mark of their own.
- The page itself is no scope. State is held only where a part of the page
  needs it.
- What the server writes into the markup for a scope to use is a `data-*`
  attribute, read through `dataset`.
- `web/lib/binds` writes what a handler runs (`submit`, `post`, `follow`, `ask`,
  `upload-picked`), and the markup names the event it runs on. A search form,
  which asks on three events, is `~search-form`.

## Consequences

- An element's markup has one attribute for each thing it binds, so a component
  adds, leaves out or passes on each one alone.
- A change made by a scope is in the page by the time the next line runs, so an
  event about it is sent at once.
- In a factory's methods and in the markup alike, `this` is the scope, so the
  element is always named `$el`.
- An inner scope reads the names of the scopes around it that it does not have
  itself.
- The ADRs written for Nomini that this one does not replace hold for Nagi,
  `nm-*` read as `n-*`.
