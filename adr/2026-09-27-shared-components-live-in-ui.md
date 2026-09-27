# Shared components live in ui/, and a page's own stay with it

*2026-09-27, restating a decision of 2026-09-25*

## Context

The components that more than one page draws had ended up in four places.
Finding where something on the screen was drawn meant knowing which one.

## Decision

- Every component shared by pages is under `web/ui/`. The ones any page may draw
  are at its top: `layout`, `icon`, `toast` and `elements`. The ones that belong
  to one part of koya are under a directory named for it: `ui/content/` for the
  editor's field controls, and `ui/media/` for the grid and the picker.
- A component under `ui/` may carry the actions it cannot work without, as the
  picker does and the layout's Log out does.
- A component used by one page stays in that page's file.
- `document.lisp` stays beside `app.lisp`. It is what the app wraps every page
  in, not something a page draws.

## Consequences

- A component that a second page starts to use moves from that page into `ui/`.
- `ui/` never uses a page, and the layers spec holds it to that.
