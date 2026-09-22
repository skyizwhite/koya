# The admin UI is Lisp, server-rendered

*2026-09-20*

## Context

The admin UI is the part of a CMS most likely to grow a front-end framework, a
build chain and a second language.

## Decision

hsx renders HTML from S-expressions, ningle-fbr routes by file path, Tailwind
(standalone binary, no Node) styles it. One hand-written JavaScript file for the
rich text editor, the media picker, and the small behaviours a page needs;
HTMX + ningle-actions where a fragment should be swapped instead of a page.

Systems are package-inferred: a file under `src/` is a package, which is also
what ningle-fbr assumes.

## Consequences

One language, one process, no build step but the stylesheet. A page is a
function, so a screen can be changed from the REPL of a running server.

Anything genuinely interactive costs hand-written JavaScript, which is the
pressure that keeps the UI plain.
