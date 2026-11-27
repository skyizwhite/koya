# A part of a page that holds state is a scope

*2026-11-27, restating a decision of 2026-11-27*

## Context

State in the browser could be kept in scripts beside the markup, or in Nagi
scopes that the markup itself names. In Nagi 0.4, `this` in `n-let-*`,
`n-bind-*` and `n-on-*` is the scope, as it is in a scope's methods, and `$el`
is the element the attribute is written on. An inner scope reads the names of
the scopes around it that it does not have itself.

## Decision

A part of a page that holds state is a Nagi scope, made by a named factory in
`assets/js/koya.js`, which is handed the scope's element as `$el` when it needs
it (`n-scope="koya.bulk($el)"`). Its elements say what they show with `n-bind-*`
and what they do with `n-on-*`, and hand themselves to what they call as `$el`.
What needs no state but has to run on an element is called from its `n-on-init`.

## Consequences

- What a part of the page does is read from its markup and its factory.
- In a factory's methods and in the markup alike, `this` is the scope, so the
  element is always named `$el`.
- An inner scope reads the names of the scopes around it.
