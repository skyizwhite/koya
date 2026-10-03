# Stored content always fits its schema

*2026-10-04*

## Context

A deploy that tightened a field's options (`required`, `unique` or `integer`
turned on, `many` switched, `maxLength` or `max` lowered, `min` raised, `pattern`
changed, a value dropped from `options`) needed `force` and left stored values
as they were. What no longer fitted stayed in published data and drafts: every
partial write and every publish of such a content failed on a field nobody had
touched, and the delivery API served values the schema no longer allowed.

Validating only the keys a write sends would have let those writes through, but
left content stored that its schema rejects. Clearing what does not fit cannot
mend a missing required value or a duplicate, and would empty a value one
character over a new `maxLength`.

## Decision

- Content as stored, published or draft, always fits the schema it is stored
  under. The history is a record of the past and is not held to it.
- A tightened option, and a `required` field added to a model that has contents,
  is checked against every stored published object and draft. What does not fit
  is listed under the change by `plan`, and the deploy is refused with
  `contents_do_not_fit`, `force` or not, until those contents are changed.
- A tightened option that everything stored fits loses nothing, and is not
  destructive: it needs no `force`.

## Consequences

- A write that merges onto stored data never fails on a field it did not send.
- Tightening becomes two steps when content is in the way: change the content
  under the old schema, then deploy. A required field for a model that has
  contents is added optional first, filled, then made required.
- Values left out of fit by deploys before this stay until written; they show
  under the next change that tightens their model's options.
