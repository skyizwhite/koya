# The admin UI is Lisp, rendered on the server

Superseded by adr/2026-10-01-the-admin-ui-is-lisp-rendered-on-the-server.md
Superseded by adr/2026-10-01-nomini-swaps-and-holds-the-pages-state.md

*2026-09-27, restating a decision of 2026-09-20*

## Context

The admin UI is the part of a CMS most likely to grow a front-end framework, a
build chain and a second language.

## Decision

- hsx renders the HTML from S-expressions, and ningle-fbr routes the pages by
  their file path.
- Tailwind styles it, from its standalone binary, with no Node.
- HTMX and ningle-actions swap a fragment where a whole page should not be
  reloaded.
- The JavaScript is one hand-written file, `assets/js/koya-editor.js`, for the
  rich text editor, the media picker and the small behaviours a page needs,
  beside the libraries it uses.

## Consequences

One language, one process, and no build step but the stylesheet. A page is a
function, so a screen can be changed from the REPL of a running server.

Anything genuinely interactive costs hand-written JavaScript, which is the
pressure that keeps the UI plain.
