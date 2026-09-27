# A referenced content cannot be deleted or unpublished

*2026-09-27, restating a decision of 2026-09-24*

## Context

A media that some content uses cannot be deleted. If a content that another one
refers to could be deleted or unpublished at will, the reference would be left
pointing at nothing: the delivery API would go on returning the id, and a site
that followed it would get a 404.

## Decision

- A content that another content refers to, in its published data or its
  draft, cannot be deleted, nor unpublished while it is published. The answer is
  `409 in_use`, from the admin API, the editor and the list's bulk actions alike.
- Unpublishing a content that is not published is not refused, since it takes
  nothing away.
- The user takes the reference out first. There is no "delete anyway".

## Consequences

Deleting a model's contents in bulk can refuse some of them because others in
the same selection refer to them. Doing it again after the referring ones are
gone completes it.

A deleted model takes its contents with it without asking; a deploy says it is
destructive.
