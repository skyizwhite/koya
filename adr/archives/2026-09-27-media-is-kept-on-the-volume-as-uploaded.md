# Media is kept on koya's own volume, as it was uploaded

Superseded by adr/2026-10-04-media-is-kept-on-koyas-own-volume.md
Superseded by adr/2026-10-04-an-upload-is-served-without-its-metadata.md

*2026-09-27, restating a decision of 2026-09-20*

## Context

A CMS needs somewhere to put the pictures. The alternatives are an object store,
which is another service and another credential, or doing it here.

## Decision

- koya writes each upload to its own volume and serves it at
  `/media/{space}/{id}.{ext}`.
- Nothing is resized or re-encoded. What is uploaded is what is served.

## Consequences

- No external storage, no image pipeline, and no dependency that decodes
  untrusted images.
- Pictures are served at whatever size they were taken. A library of
  photographs sends them all at full size to draw its own grid.
