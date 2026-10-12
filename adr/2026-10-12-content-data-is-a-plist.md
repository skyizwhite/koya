# A content's data is a plist

*2026-10-12*

## Context

A content's data has the shape its schema gives it: fields a site names, a
custom field holding fields of its own, a repeater holding rows. Once
[JSON stays at the edges](2026-10-12-json-is-converted-at-the-edges.md), this
data needs a Lisp form that tells apart what the domain decides on: a field with
no value, a false boolean, an empty list and a field being cleared. Its keys are
names a site chose, and data from outside may carry any key at all.

## Decision

- An object is a plist whose keys are the fields' names as kebab-case
  keywords, `eventAt` as `:event-at`, converted
  [without loss](2026-10-12-keys-convert-between-camelcase-and-kebab-case-without-loss.md).
  A row of a repeater is a plist with its custom field's name under
  `:field-id`.
- An array, the values of a `many` field or the rows of a repeater, is a vector.
- A boolean is `t` or `nil`.
- Stored data has no null: a field without a value has no key. A patch clears a
  field by giving it `:null`, and an edge writes `null` where an answer needs
  one.
- Converting data from outside never interns a symbol: a key becomes a keyword
  only when one already exists that converts back to exactly that key, and
  otherwise stays a string. A schema interns its fields' keywords when it is
  read, so every field's key is found. A key that names no field is refused as
  `unknown_field`, whether it became a keyword that exists for another reason,
  such as `:name`, or stayed a string. Data koya stored itself has only fields
  as keys and is converted with them interned.

## Consequences

- The domain reads and changes data in Lisp terms, without a JSON null or a
  hash table in sight.
- An empty object and `false` are both `nil`: a custom field given `false` is
  taken as given an empty object, where it was refused as not an object. What
  koya writes for others to read, the APIs' answers and the webhooks, is made
  knowing the schema and has a custom field's `nil` as `{}`; what it stores and
  exports for itself may hold `false` there, which it reads back as the same
  `nil`.
- Each field name has a keyword of its own, so two names that differ only in
  case, `eventAt` and `eventat`, never read each other's value.
- No request can make the server intern a name a schema has not.
