# An object model refuses a second content

*2026-10-04*

## Context

An object model holds exactly one content. Creating a content on one that had
its content already updated that one instead: a draft save, or a publish with
`publish`. So one call did different things depending on what was stored, and
a create could answer `201` for a content made long before, having only
changed it.

## Decision

Creating a content on an object model that has its content is refused with
`409 object_exists`, and nothing is written or sent. That content is changed
through its model's routes.

## Consequences

Creating always makes a content, and its webhook is always `draft` or `publish`
with no `old`. A caller writing an object model saves a draft at the model,
which makes the content the first time, or creates it and on `object_exists`
changes it at the model.
