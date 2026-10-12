# Dropping a custom field from a repeater is destructive

*2026-10-12*

## Context

A repeater's rows each name a custom field from its `customFields`. Taking one
out is an options change, checked as a tightening: a deploy is refused while a
published object or draft still holds a row of it. The history is not checked,
and rows of it left in the revisions come back under whatever the custom field
holds if it is listed again. A deploy therefore takes those rows out of every
revision, which loses data the way removing a field does.

## Decision

A `change_field_options` that drops a custom field from a repeater's
`customFields` is destructive, and a deploy with one needs `force` as removing a
field does. Adding one stays an ordinary options change.

## Consequences

`plan` marks such a change with `!`, and a deploy without `force` is refused
with `destructive_changes` after the contents are checked. The deploy log
counts it as destructive.
