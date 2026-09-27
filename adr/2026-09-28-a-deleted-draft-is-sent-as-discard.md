# A deleted draft is sent as discard

*2026-09-28*

## Context

Deleting a content sent `delete` whether or not it had been published. The docs
say what each event changes: `draft` and `discard` change only a draft, and
`publish`, `unpublish` and `delete` change what the delivery API serves. A
content that was only a draft was never served, so its `delete` changed only a
draft, and a site that acted on `delete` revalidated pages that had not changed.

## Decision

Deleting a content is sent as what it changes:

- a content that was published, with a draft or not, as `delete`, with the
  published data as `old` and `null` as `new`;
- a content that was only a draft as `discard`, with the draft as `old` and
  `null` as `new`.

## Consequences

An event's name alone says whether what the delivery API serves changed.
`discard` means a draft went away: thrown back to the published data, which is
its `new`, or deleted with the content, when `new` is `null`.
