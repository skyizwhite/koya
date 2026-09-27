# A bulk action with nothing to do to a content leaves it alone

Superseded by adr/2026-09-28-a-bulk-action-skips-what-would-change-nothing.md

*2026-09-27, restating a decision of 2026-09-23*

## Context

A bulk selection mixes contents in different states. Publishing a content that
is already published with no draft, or unpublishing one that is not published,
would still move its `revisedAt` or reissue its draft key if it went through.

## Decision

A bulk Publish skips a content that is published and has no draft. A bulk
Unpublish skips a content that is not published. A skipped content is counted
as skipped, not as done or failed.

## Consequences

Selecting everything and publishing changes only what needed it.
