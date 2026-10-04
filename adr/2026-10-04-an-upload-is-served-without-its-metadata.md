# An upload is served without its metadata

*2026-10-04*

## Context

Media is served at a public URL without a key. A photo from a phone carries
EXIF, XMP and the like: the camera, the time, and the GPS position where it was
taken, so publishing a picture could publish where the owner lives. Removing
them by decoding and re-encoding the image would need a dependency that decodes
untrusted images, and would change the pixels.

## Decision

- Nothing is resized or re-encoded: the image data is served as it was
  uploaded.
- What describes the picture rather than draws it is taken out on upload, by
  walking the file's segments or chunks: in JPEG the APP1 (EXIF, XMP), APP13,
  the other application segments but JFIF, ICC and Adobe, comments, the
  multi-picture index and whatever follows the end of the image; in PNG `eXIf`,
  `tEXt`, `zTXt`, `iTXt` and `tIME`; in WebP the `EXIF` and `XMP ` chunks. GIF is
  kept as it is.
- The orientation is kept, alone, in an EXIF of its own, so a photo taken
  upright is shown upright. The colour profile is kept.
- A file whose structure ends early is kept as far as it can be walked, and the
  rest as it is.
- Media uploaded before this keeps its metadata until it is uploaded again.

## Consequences

- No image pipeline and no dependency that decodes images.
- A stored file is smaller than the upload, and its size is what is stored.
- Pictures are served at whatever size they were taken. A library of
  photographs sends them all at full size to draw its own grid.
