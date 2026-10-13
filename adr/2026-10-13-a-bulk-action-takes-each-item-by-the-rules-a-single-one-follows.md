# A bulk action takes each item by the rules a single one follows

*2026-10-13, restating a decision of 2026-09-23*

## Context

When every action works on one content, publishing ten drafts means ten trips
through the editor.

A bulk action went through the path a single one takes for each item, reads
included: a content was read once to decide whether to skip it and again by the
action, and each media removed loaded the schema and looked through the
contents that mention it. Other pages read what they show for a whole page
together.

## Decision

- Checkboxes select rows of the content list for Publish, Unpublish and Delete,
  and cards of the media library for Delete.
- Each selected item is checked and changed by the same rules, with the same
  messages, as a single one, so validation, timestamps, reference checks and
  webhooks behave as they do for one. What the selection needs is read
  together where an item's change does not depend on reading it at that
  moment.
- A content is still read and changed in its own transaction, which decides
  whether it is skipped, so what is written follows the row as it is then.
  The media of a selection, and how many contents use each, are read once.
- An item that fails leaves the others done, and the answer says how many were
  done, skipped and failed.

## Consequences

Deleting in bulk can refuse some items because others in the same selection
refer to them; doing it again after those are gone completes it.

A selection of media is checked against the contents as they were when it was
read, as a single removal is checked before it removes.

Bulk actions need JavaScript: the bar is hidden until something is selected.
