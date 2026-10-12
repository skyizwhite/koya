# A field's value is found by its keyword alone

*2026-10-12*

## Context

[Structured data is read and changed through access](2026-10-12-structured-data-is-read-and-changed-through-access.md).
`access` compares keys with `equalper`, which takes a symbol by its name and
compares names without case: the string `"blog-post"` is found as `:blog-post`,
and setting `:blog-post` on a plist that holds `"blog-post"` replaces that
entry. Data from outside keeps a key that is no field's keyword as a string
([a content's data is a plist](2026-10-12-content-data-is-a-plist.md)), so a
patch `{"blog-post": 1}` merged onto a content would become the field
`blogPost`'s value and never be refused as `unknown_field`.

## Decision

- A field's value is read with `field-value` and set with `setf` on it, both in
  `koya-core/schema`. They find the field's key with `eq`.
- What reads or changes data by a key that is not a field's, merging a patch,
  a row's `fieldId`, a key of a stored schema's renamed field, passes
  `:test #'eq` to `access` itself.

## Consequences

- A key that stayed a string is never taken for a field, whatever its spelling,
  and validation names it as it came.
- Code that reads a content's data reads it by field, and the rule for keys is
  in one place.
- Data built in a spec has keyword keys and reads the same through `access`
  with its default test.
