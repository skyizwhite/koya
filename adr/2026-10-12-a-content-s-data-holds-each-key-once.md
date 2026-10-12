# A content's data holds each key once

*2026-10-12*

## Context

[A content's data is a plist](2026-10-12-content-data-is-a-plist.md). A plist
can hold a key twice, and code that reads or compares one could guard against
that: look for a second entry, refuse it, or compare both ways so that a key
given twice is caught. Every such guard is work done on every read and
comparison, and a comparison made to catch it both ways doubles its work at
each level of nesting.

## Decision

- A content's data, and each object inside it, holds each key once.
- What makes data keeps it so: data from outside and from storage is converted
  from JSON objects, which hold a key once; a field is set with `setf` on
  `field-value` or `access`, which replaces a key that is there; a form gives
  each field once. What lists keys itself, a fitted shape, a form's data or a
  restored version, gives each field of the model or custom field once and a
  row's `:field-id` last, so it relies on a model's and a custom field's field
  names being distinct and on no field inside a custom field being named
  `fieldId`, which the schema refuses.
- What reads or compares data relies on this and does not check it.
  `data-equal` compares an object one way: the same number of entries, and each
  of the one found in the other with an equal value.

## Consequences

- Reading and comparing data stay linear in its size.
- A plist that holds a key twice is no content data, and what any function
  makes of it is not specified; specs do not give one.
- A review finding about a key given twice is about data no caller makes, and
  is set aside.
