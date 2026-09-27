# An object model refuses a second content

*2026-09-28*

## Context

An object model holds exactly one content. Creating a content on one that had
its content already updated that one instead: a draft save, or a publish with
`publish`. So one call did different things depending on what was stored, and
a create could answer `201` for a content made long before, having only
changed it.

## Decision

Creating a content on an object model that has its content is refused with
`409 object_exists`, and nothing is written or sent. That content is changed
through its id, like any other: a draft save, a publish, a discard.

## Consequences

Creating always makes a content, and its webhook is always `draft` or `publish`
with no `old`. A caller writing an object model reads it first, or creates it
and on `object_exists` reads it and changes it by id.
