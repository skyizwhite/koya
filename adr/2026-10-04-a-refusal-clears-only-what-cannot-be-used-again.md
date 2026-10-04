# A refusal clears only what cannot be used again

*2026-10-04*

## Context

A refused action answers the place for its reason under its id, and leaves the
rest of the page as it was. Some refusals drew a whole card, form or editor
instead, which cleared what had been typed: a time zone name to correct, every
field of the editor. Leaving every input as it is would be wrong the other way
for a few: a one-time code is good for thirty seconds, and a secret typed into a
password box cannot be seen to be corrected.

## Decision

- A refusal keeps what was typed when the owner corrects it and sends it again:
  the time zone name, the editor's fields. It answers the reason's place only:
  `#time-zone-error`, and in the editor `#editor-errors` with each field's own
  error line, a field without an error answered with its line empty.
- A refusal clears what cannot be sent again as it is. A wrong two-factor code,
  when turning two-factor login on or off, answers the form it was typed in, its
  code empty and its reason inside; the QR code and the secret stay. A failed
  login answers the whole login form, its secret and code empty.
- An answer that succeeds draws again what it changed, as before: the editor
  after a save or a publish, since what is stored may differ from what was sent
  (a slug filled in, a value normalised, the new `updated-at`).

## Consequences

- Each place a reason is drawn has an id, drawn hidden while there is nothing to
  say, so a refusal can be answered into it.
- What a refused answer holds says what it resets: an input among the ids at
  its top is one the owner types again.
