# A datetime is kept to the minute in UTC

*2026-10-02*

## Context

A `datetime` field took any ISO 8601 value with a zone and stored it as sent.
The editor's `datetime-local` input goes to the minute, so saving a content
whose datetime had seconds dropped them although nobody touched the field, and
a value given with an offset was stored with it, so text comparison sorted and
filtered it out of order. Asking for seconds in the editor would make them part
of every entry, and Chromium leaves the input empty until they are typed.

## Decision

- A `datetime` value is stored to the minute, in UTC, in the form `format-iso`
  writes: whatever the zone it was given in, and whatever seconds it had, which
  are dropped rather than refused.
- It is brought to that form on every write — creating, saving a draft and
  publishing — before a save is compared with what is stored.

## Consequences

- What the editor draws is what is stored, so a save that touches no datetime
  changes none.
- A site sending `new Date().toISOString()` gets the minute it is in.
- A save that differs from the stored value only in its seconds is no change.
- Values stored before this keep their seconds and offset until the content is
  written again.
