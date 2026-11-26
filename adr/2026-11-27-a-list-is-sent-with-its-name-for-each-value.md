# A list is sent with its name for each value, and a select option holds no comma

*2026-11-27, restating a decision of 2026-10-02*

## Context

A form sends a list -- a selection of contents or media, a many-reference field,
a many select -- by giving a name more than once, and Nagi sends a form, or an
array it is handed, the same way. Before, the admin UI sent a list as its values
joined with commas, and the actions read a list by splitting what they are sent
on commas; a select's option was made to hold no comma for that.

## Decision

- The admin UI sends a list with its name given once for each value.
- The actions read a list from every value given under its name, and split each
  value on commas as well.
- A select's option holds no comma; a schema with one is refused when it is
  deployed or planned. It is not refused when it is read: a schema stored or
  exported before this rule is read, and imported, as it is.

## Consequences

- A list is read the same way however it is sent, a form posted by hand or a
  list joined with commas included.
- A schema whose options carried a comma has to change them before its next
  deploy. Until then, a content with such an option chosen in a many select
  cannot be saved from the admin UI: the option is split at the comma, and the
  parts are refused as options the field does not have.
