# What a unique constraint holds is decided by the insert

*2026-10-13*

## Context

The database already refuses what must be unique: a media's id across spaces, a
content's id within its space, and a key's id and hash. An upload and a new
content insert the id they draw and draw again when it is taken. An import,
though, looked each of its media and keys up before writing, to refuse one
another space held, and a new key was inserted without asking whether it was
kept. A look-up made before the insert can be passed by another write between
the two, so it is the constraint that decides either way, and the look-up
repeats it with a read for each media or key.

## Decision

- What a unique constraint holds is not looked up beforehand. The insert keeps
  a row the constraint takes and tells when it does not, without failing, and
  the use case acts on that: it draws another id or key for one it made, and
  refuses, naming what was taken, one it was given.
- What no constraint holds is still checked before anything is written: that an
  import's space is empty, an archive's shape and contents, and what repeats
  inside the archive itself.

## Consequences

- An import refuses a media or a key another space holds once it reaches the
  insert, after the media files are written; its transaction is undone and the
  files it wrote are taken away, so nothing is left, as before.
- Nothing reads what is taken before inserting: an import makes no read for
  each media or key it brings.
- A store's insert says whether it kept the row, and each caller acts on that.
