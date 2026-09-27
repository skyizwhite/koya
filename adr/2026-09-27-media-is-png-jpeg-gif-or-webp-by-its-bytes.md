# Media is PNG, JPEG, GIF or WebP, known by its bytes

*2026-09-27, restating a decision of 2026-09-20*

## Context

The media library serves what it is given, from koya's own origin. What a
browser says a file is cannot be trusted, and some image formats can carry
scripts.

## Decision

- Only images are accepted: PNG, JPEG, GIF and WebP.
- The format is decided by reading the file's leading bytes, not by the type
  the upload claims.
- SVG is refused.

## Consequences

- A file that is not one of the four is refused, whatever its name or type says.
- A site that wants a vector image has to put it somewhere other than koya.
