# An action answers the part of the page it changed

*2026-09-27, restating a decision of 2026-09-25*

## Context

An action should not draw the whole page again. It should say what came of it
without a reload.

## Decision

- An action answers with the part of the page it changed, drawn again whole
  under its id (`#library`, `#editor`, `#contents` and so on). The toast goes
  out of band into the layout's `#toast`.
- A refused action leaves the page alone (`HX-Reswap: none`) and says why in the
  toast. Where the page has a place for the reason, such as a dialog's error
  line, the answer is retargeted there instead.
- An action whose result is another page sends the browser there with
  `HX-Redirect`. A content just made, one deleted and a space imported all work
  this way, and the toast waits in the session.

## Consequences

The editor, the lists and the library change in place, without the page being
drawn again.
