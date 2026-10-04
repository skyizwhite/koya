# Media is kept on koya's own volume

*2026-10-04, restating a decision of 2026-09-20*

## Context

A CMS needs somewhere to put the pictures. The alternatives are an object store,
which is another service and another credential, or doing it here.

## Decision

koya writes each upload to its own volume and serves it at
`/media/{space}/{id}.{ext}`.

## Consequences

No external storage: the volume that holds the database holds the media, and a
backup of it is a backup of both.
