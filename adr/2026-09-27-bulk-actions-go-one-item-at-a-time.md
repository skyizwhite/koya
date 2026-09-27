# A bulk action takes each item one at a time, through the path a single one takes

*2026-09-27, restating a decision of 2026-09-23*

## Context

When every action works on one content, publishing ten drafts means ten trips
through the editor.

## Decision

- Checkboxes select rows of the content list for Publish, Unpublish and Delete,
  and cards of the media library for Delete.
- Each selected item goes one at a time through the path a single one takes, so
  validation, timestamps, reference checks and webhooks behave as they do for
  one.
- An item that fails leaves the others done, and the answer says how many were
  done, skipped and failed.

## Consequences

Deleting in bulk can refuse some items because others in the same selection
refer to them; doing it again after those are gone completes it.

Bulk actions need JavaScript: the bar is hidden until something is selected.
