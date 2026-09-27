# Archives are kept beside the database

*2026-09-27, restating a decision of 2026-09-25*

## Context

An archive being sent or uploaded is as large as a space, so it needs a place
with the room a space has.

## Decision

- Archives are kept in `archives/` beside the database, on the volume.
- What an export or an upload left behind a day or more ago is deleted when the
  next one starts.

## Consequences

- An upload that was given up is deleted a day later.
- `archives/` may be left out of backups.
