# A space is exported and imported through the admin UI only

*2026-09-27, restating a decision of 2026-09-23*

## Context

An export and an import could be offered by the admin API as well as the admin
UI. A management key reaches one space, and an import that makes a space would
need a key for a space that does not exist yet. Only the owner can make spaces.

## Decision

- **Export** is on a space's page and downloads the zip.
- **Import** is on the spaces page.
- Neither has an API.

## Consequences

Moving a space takes the owner, signed in to both instances.
