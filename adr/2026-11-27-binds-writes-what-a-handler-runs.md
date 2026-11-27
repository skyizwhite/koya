# binds writes what a handler runs

*2026-11-27, restating a decision of 2026-11-27*

## Context

What an element runs when an event fires is JavaScript written by Lisp. It could
be written in full where each element is drawn, or by functions that write it
the same way everywhere.

## Decision

`web/lib/binds` writes what a handler runs (`submit`, `post`, `follow`, `ask`),
and the markup names the event it runs on. A search form, which asks on three
events, is `~search-form`.

## Consequences

- A request is written one way wherever it is sent, and the markup says only
  when.
- A change to how a kind of request is sent is made in one place.
