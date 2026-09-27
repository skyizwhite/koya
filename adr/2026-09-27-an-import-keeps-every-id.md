# An import keeps every id

*2026-09-27, restating a decision of 2026-09-23*

## Context

Contents refer to each other by id, media fields hold media ids, and richtext
holds `/media/{space}/…` paths that name a file by its id.

## Decision

- An import keeps the ids of contents, media and keys. A content's history comes
  back in its order, with its authors and times.
- Media ids become file names, so each one is checked against the shape an
  upload makes, and each file is sniffed as an upload is.

## Consequences

Reference fields, media fields and the paths in richtext all still point at the
right things.
