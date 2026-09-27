# The content list is searched, filtered and sorted through the delivery API's query

*2026-09-27, restating a decision of 2026-09-23*

## Context

A list that shows every content of a model, newest first, with only a page
number, makes finding one among a few hundred a matter of paging.

## Decision

- The content list has a search box, a status filter and sortable column
  headers. Their state is in the query string, so a list as it is being read is
  a link (see [lists are read in place](2026-09-25-lists-are-read-in-place-and-the-url-follows.md)).
- They are asked through `domain/query`, the same query the delivery API uses
  for its filters and order over the JSON, rather than a second way of asking.
- The search covers the text, textarea, slug and richtext fields, and the
  content id. The id is matched whole, because ids made in the same period
  share a prefix.

## Consequences

The list is usable at a few hundred contents without a second query path to
maintain.
