# A draft that changes nothing is none

*2026-09-25*

## Context

`adr/2026-09-23-every-write-to-a-content-is-kept.md` records every write, but a
draft save that changes nothing against the newest revision records nothing.
The save still wrote a draft: the content became `published+draft` with a fresh
draft key, and **Discard draft** appeared. Discarding it then recorded a
`discard` whose data was the version just before it, so the history showed an
entry with no change -- one kind of write skipped when it changed nothing, the
other kept.

## Decision

A draft that changes nothing is not made. Saving what the content holds already
writes nothing at all: no draft, no revision, no webhook. Saving the published
data again, over a draft that differed, drops the draft, and that is kept as a
`discard`, which has the change back to show. In the editor, **Save draft** is on
only while the form holds a change.

Publishing is unchanged: publishing the same data again moves `revisedAt` and
fires the webhooks, so it is a write the site sees, and it is kept.

## Consequences

Every entry in a content's history shows a change, or a publish. A PATCH through
the admin API that ends where it started answers the content as it is and sends
nothing.
