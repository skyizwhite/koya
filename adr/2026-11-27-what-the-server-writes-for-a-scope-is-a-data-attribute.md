# What the server writes for a scope is a data attribute

*2026-11-27, restating a decision of 2026-11-27*

## Context

A scope often needs values only the server knows, such as the URLs of its
actions or a size limit. They could be written into the scope's expression or
onto its elements. In Nagi 0.4, a scope's element's `data-*` are not names of
the scope; they are read with `$el.dataset` or `$dataset()`.

## Decision

What the server writes into the markup for a scope to use is a `data-*`
attribute, read through `dataset`.

## Consequences

- A factory in `koya.js` reads its element's `dataset` for what the server
  wrote, and the expression in `n-scope` stays a call.
- A `data-*` attribute is a constant of the page as drawn; what changes is a
  member of the scope.
