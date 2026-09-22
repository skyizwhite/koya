# The content list can be searched, filtered, sorted, and acted on in bulk

*2026-09-23*

## Context

The list showed every content of a model, newest first, with `?page=` as the
only control. Finding one among a few hundred meant paging. And every action
worked on one content, so publishing ten drafts meant ten trips through the
editor.

## Decision

A search box, a status filter and sortable column headers, all in the query
string so that a list as it is being read is a link. They go through
`lib/query` — the delivery API's own WHERE and ORDER BY over the JSON — rather
than a second way of asking. The search covers the text-ish fields and the
content id, the id matched whole because ids made in the same period share a
prefix.

Checkboxes select rows for Publish, Unpublish and Delete; the media library
selects for Delete. Each item goes one at a time through the path a single one
takes, so validation, timestamps and webhooks behave as they do for one, and one
that fails leaves the rest done. An action with nothing to do to an item — 
publishing what is published, unpublishing a draft — leaves it alone rather than
moving its `revisedAt` or reissuing its draft key.

Every list in the admin UI shows 20 rows.

## Consequences

The list is usable at a few hundred contents without a second query path to
maintain. Bulk actions need JavaScript: the bar is hidden until something is
selected.
