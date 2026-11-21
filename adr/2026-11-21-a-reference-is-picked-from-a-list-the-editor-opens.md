# A reference is picked from a list the editor opens

*2026-11-21*

## Context

The editor drew a reference field as a dropdown, or as chips over a hidden
multiple select, holding every content of the target model. Drawing the form
listed each target model whole, however many contents it had, and the
dropdown offered nothing to find one by but scrolling. A `many` reference kept
its order only as the select held it, so it could not be rearranged, and what
was chosen showed only as a label, with no way to open it.

## Decision

- A reference field shows what it holds as cards: the label and the status of
  each content, linked to its editor, with a × to take it out. A `many` one's
  cards are reordered as a repeater's rows are, by dragging or by arrows.
- Contents are chosen from a dialog, as media are: **Select…** or **Add…**
  opens it on the target model's contents, which it fetches a page at a time
  and searches as the content list does. A `many` field takes several at once
  and is not offered what it holds already.
- The form reads only the contents its fields hold, those of one model
  together, and lists no model.

## Consequences

- Opening the editor costs the same however many contents a target model has;
  the picker reads them only when it is opened.
- The card the dialog hands over is drawn by the server, so a card added in
  the browser looks like one the editor drew.
- A form whose JavaScript has not run cannot choose a reference; the editor
  needed it for the chips and the media already.
