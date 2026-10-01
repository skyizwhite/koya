# A list is sent comma-separated, and a select option holds no comma

*2026-10-02*

## Context

A form sends a list -- a selection of contents or media, a many-reference field,
a many select -- by giving a name more than once. Nomini's `$get` and `$post`
send an object, so a name is given once, and an array is sent as its values
joined with commas. The ids koya makes hold no comma, but a select's options
were any strings.

Sending each list as JSON would carry any value, at the cost of a rule of its
own for lists alone.

## Decision

- The admin UI sends every list as Nomini sends an array: its values joined
  with commas. The actions read a list by splitting what they are sent on
  commas.
- A select's option holds no comma; a schema with one is refused when it is
  deployed.

## Consequences

- A list is read the same way wherever it is sent from, a form posted by hand
  included.
- A schema whose options carried a comma has to change them before its next
  deploy.
