# A duplicate is stored when it is saved

*2026-11-21*

## Context

A content is duplicated to start another like it: a product beside a product, a
post that follows the shape of the last one. The copy cannot keep the
original's `slug` or `unique` values, which another content already holds, so
they are left empty.

Two ways were open: **Duplicate** stores a new draft at once and opens it, or it
opens a new content's editor holding the copy and stores nothing until it is
saved.

## Decision

**Duplicate** opens the editor of a new content, filled with the original's
values less its `slug` and `unique` fields, and nothing is stored until the
copy is saved or published, through the same path as any new content.

The admin API has no duplicate: a site that wants one reads the content and
creates another with what it read.

## Consequences

- A copy whose model has a required `unique` field is not refused for the
  value it lacks before anyone could type one: the editor asks for it on save,
  as on any new content.
- A copy that is opened and left makes no content, no history and no webhook
  call.
- The use cases have no duplicate: saving a copy is creating a content.
