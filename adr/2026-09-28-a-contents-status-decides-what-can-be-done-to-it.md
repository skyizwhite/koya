# A content's status decides what can be done to it

*2026-09-28*

## Context

Each operation on a content checked its own conditions. Discarding a draft-only
content was refused, but discarding a published one with no draft answered 200
having done nothing, and unpublishing a draft answered 200 having moved its
`updatedAt` and reissued its draft key, so its preview links stopped working.
What a caller could do in each status was spread across the operations and not
the same from one to the next.

## Decision

- A content's status (`draft`, `published`, `published+draft`) and an operation
  (save a draft, publish, unpublish, discard the draft, delete) decide, from one
  table, the status the content goes to, or a refusal.
- Every pair is in the table as one or the other. A refusal is a `409` with a
  code that says why, and nothing is written or sent:
  - unpublishing a draft: `not_published`
  - discarding the draft of a draft: `not_published`
  - discarding with no draft: `no_draft`
- Publishing a published content is a transition to itself, not a refusal:
  it moves `revisedAt`, can take a new `publishedAt`, and is sent as `publish`.
- Saving what the content holds already is not in the table: it writes nothing
  and answers the content as it is, as
  `adr/2026-09-25-a-draft-that-changes-nothing-is-none.md` has it. Saving the
  published data again is the discard transition.
- A refusal the table makes comes before any other check: unpublishing a draft
  that others refer to is `not_published`, not `in_use`.

## Consequences

An operation that answers 200 always changed the content. The admin UI shows
only what the table allows, so a refusal reaches only an API caller.
