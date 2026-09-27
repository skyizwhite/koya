# Media is images, on the volume, unaltered

Superseded by adr/2026-09-27-media-is-kept-on-the-volume-as-uploaded.md
Superseded by adr/2026-09-27-media-is-png-jpeg-gif-or-webp-by-its-bytes.md
Superseded by adr/2026-09-27-a-media-field-refers-to-the-spaces-library.md
Superseded by adr/2026-09-27-the-delivery-api-expands-a-media-field.md

*2026-09-20*

## Context

A CMS needs somewhere to put the pictures. The alternatives are an object store
(another service, another credential) or doing it here.

## Decision

koya stores uploads on its own volume and serves them at
`/media/{space}/{id}.{ext}`. Images only — PNG, JPEG, GIF and WebP — and the
format is decided by reading the file's leading bytes, not by what the browser
claims. SVG is refused. Nothing is resized or re-encoded.

Media belongs to a space's library, and a `:media` field references a file in it
rather than carrying a file of its own. The library is reached from its own page
and from a modal in the editor; both are the same component.

The delivery API always expands a `:media` field into an object with its URL,
without being asked: an image id alone cannot be used, and the expansion cannot
nest.

## Consequences

No external storage, no image pipeline, no dependency that decodes untrusted
images. The same picture can be used by several contents, and a file some
content still uses cannot be deleted.

What is uploaded is what is served, at whatever size it was taken: a library of
photographs sends them all at full size to draw its own grid.
