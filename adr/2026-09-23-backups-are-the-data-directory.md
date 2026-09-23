# Backups are the /data directory; moving data is Export and Import

*2026-09-23*

## Context

The design planned a `POST /admin/api/backup` that would `VACUUM INTO` a copy
of the database, as a later phase (#7). It was meant both for keeping a copy of
the instance and for getting data out. A space can now be exported as a zip and
imported again (adr/2026-09-23-a-space-moves-as-one-zip-through-the-admin-ui.md),
which covers the second.

## Decision

koya has no backup mechanism of its own. A backup is the whole `/data`
directory, which holds the database and the uploaded media; how it is taken is
the operator's choice. Moving data is a space's Export and Import. #7 is closed
as not planned.

## Consequences

Restoring is putting `/data` back and starting the server; the migrations bring
an older database up to date.
