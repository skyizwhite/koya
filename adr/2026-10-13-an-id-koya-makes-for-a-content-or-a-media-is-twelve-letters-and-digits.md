# An id koya makes for a content or a media is twelve letters and digits

*2026-10-13, restating a decision of 2026-10-10*

## Context

Of the ids koya makes, those of contents and media are the ones people see. A
site puts a content's id in its URLs, `/blog/01J8Q0Z5X2W3V4U5T6S7R8Q9P0`, and
every file it serves is at a media's id, `/media/<space>/<id>.png`, in its pages,
its rich text and the delivery API's answers. Both were ULIDs, 26 characters.
What a ULID gives beyond being unique, ids that sort in the order they were
made, is not used for either: contents are ordered by `createdAt`, and the
media library by when a file was uploaded, an id only breaking ties.

Ten characters from upper- and lowercase letters and digits were weighed for
contents: two fewer characters, but ids that differ only in case are easy to
misread and to mistype, and some tools fold case.

## Decision

- An id koya makes for a content or a media is 12 characters from the lowercase
  letters and the digits, chosen at random.
- A content's id is drawn again when its space already holds it. A media's id is
  drawn again when any space holds it, since a media id is unique across
  spaces.
- Ids from before stay as they were: ULIDs, or ids contents were created with.
  What reads a media id, a file's URL or an archive, takes both a short id and a
  ULID.

## Consequences

- About 62 bits, 36^12 ids: with a million contents in a space, or a million
  media in all, a draw comes out taken about once in five trillion, and a taken
  one only means another draw.
- Nothing is rewritten: an id from before keeps its shape, and every shape
  fits what an id may be.
- An id no longer tells when it was made, and a list ordered by `id` is in the
  order of the ids' text.
