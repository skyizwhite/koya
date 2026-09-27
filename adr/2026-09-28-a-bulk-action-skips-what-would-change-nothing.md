# A bulk action skips a content it would do nothing to

*2026-09-28, restating a decision of 2026-09-23*

## Context

A bulk selection mixes contents in different statuses. Unpublishing a draft is
refused, and publishing a published content with no draft is allowed but only
moves its `revisedAt` and sends `publish`. Neither is what someone selecting
everything meant.

## Decision

A bulk action skips a content that the status table
(`adr/2026-09-28-a-contents-status-decides-what-can-be-done-to-it.md`) refuses
the action for, or that the action would leave in the status it is in. A
skipped content is counted as skipped, not as done or failed.

## Consequences

Selecting everything and publishing changes only what needed it, and a mixed
selection unpublished reports the drafts as not published rather than as
failures.
