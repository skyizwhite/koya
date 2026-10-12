# The history names ids one at a time

*2026-10-13*

## Context

Delivery, the content list, the editor and a restore read the references and
media a content holds together: they collect the ids and read them with
`find-contents-by-ids` once per target model and `find-media-by-ids` once.

The history page shows, for each version on a page, the fields that version
changed, and names a reference or a media in them by its label or file name.
It names each id with its own reads: the target model with `find-model` and the
content with `find-content`, or the media with `find-media`.

Measured on a SQLite file, naming 200 references one at a time took about
5–7 ms, and reading them together about 1 ms. A page holds about 21 versions
and shows only what each changed, so even a gallery of 10 media changed in
every version comes to about 10–15 ms, on a page only the owner opens.
Reading them together would mean collecting the ids of every version on the
page and threading a function that names an id through `~revision`, `~changes`
and `~value`.

## Decision

The history page names each reference and media it shows with its own reads.

## Consequences

- A history page makes reads in proportion to the references and media its
  versions changed, and its components take the space rather than what was
  read for them.
- The page is the one place that reads what data holds one id at a time. If a
  history page ever takes tens of milliseconds to name its ids, it is the first
  to read them together.
