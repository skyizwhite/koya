# A content id koya makes is twelve letters and digits

*2026-10-10*

## Context

A content id koya made was a ULID, 26 characters, and a site that puts the id
in its URLs carried all of them: `/blog/01J8Q0Z5X2W3V4U5T6S7R8Q9P0`. What a
ULID gives beyond being unique — ids that sort in the order they were made — is
not used for contents, whose order is their `createdAt`.

Ten characters from upper- and lowercase letters and digits were weighed: two
fewer characters, but ids that differ only in case are easy to misread and to
mistype, and some tools fold case.

## Decision

A content id koya makes is 12 characters from the lowercase letters and the
digits, chosen at random. One that its space already holds is drawn again.
Media, keys and deploys keep their ULIDs.

## Consequences

- About 62 bits, 36^12 ids: with a million contents in a space, a draw comes out
  taken about once in five trillion, and a taken one only means another draw.
- Ids from before stay as they were, ULIDs or ids contents were created with;
  nothing is rewritten, and every shape fits what an id may be.
- A content id no longer tells when it was made, and a list ordered by `id` is
  in the order of the ids' text. A list ordered by `createdAt` is in the order
  of those dates, which an import may have given.
