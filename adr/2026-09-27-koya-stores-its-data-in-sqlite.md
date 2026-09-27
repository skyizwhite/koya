# koya keeps its data in SQLite, with plain SQL

*2026-09-27, restating a decision of 2026-09-20*

## Context

koya is a CMS for one owner and a handful of sites, run as one process. A
database server would be another service to run, back up and upgrade.

## Decision

- The data is one SQLite file on koya's volume.
- The store writes SQL itself through cl-dbi. There is no ORM or query builder,
  and no layer that would let another database stand in.

## Consequences

- There is no second database to support, so nothing is written twice.
- Backing up the data is copying a file.
- koya is limited to what SQLite does well enough at this size.
