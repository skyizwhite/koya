# An action answers the elements of the page it changed

*2026-10-01, restating a decision of 2026-09-25*

## Context

An action should not draw the whole page again. It should say what came of it
without a reload.

## Decision

- An action answers with each part of the page it changed, drawn again whole
  under its id (`#library`, `#editor`, `#contents`, the count beside a list, and
  so on). The toast is one of them: the layout's `#toast`.
- A refused action answers the toast with the reason, and nothing else, so the
  page is left as it was. Where the page has a place for the reason, such as a
  dialog's error line, it answers that place under its id instead.
- An action whose result is another page sends the browser there with
  an element swapped into the document's `#location`. A content just made, one deleted and a space imported all work
  this way, and the toast waits in the session.

## Consequences

The editor, the lists and the library change in place, without the page being
drawn again. What an answer changes can be read from the ids at its top.
