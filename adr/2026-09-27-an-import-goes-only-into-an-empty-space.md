# An import goes only into a space that has nothing to meet

*2026-09-27, restating a decision of 2026-09-23*

## Context

Merging an archive into a space that already holds contents, media or keys would
need rules for every clash, by id, by schema or by file.

## Decision

- The name must be free, or the space must be empty: no models (so no
  contents), no media and no keys. Its webhooks and webhook secret, which a new
  space has from the start, are replaced by the archive's.
- Anything else is refused and changes nothing. There is no merge by id, and no
  check that the deployed schema matches the archive's.
- The import owns the schema, webhooks included, and records it in the deploy
  log as a deploy by whoever imported it.
- An existing media file is never replaced.

## Consequences

- A schema that has moved on since the export does not stop the import, because
  the import brings its own. Deploying the site's current schema afterwards is an
  ordinary deploy.
