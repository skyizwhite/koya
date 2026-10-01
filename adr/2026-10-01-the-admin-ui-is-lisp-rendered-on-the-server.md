# The admin UI is Lisp, rendered on the server

*2026-10-01, restating a decision of 2026-09-20*

## Context

The admin UI is the part of a CMS most likely to grow a front-end framework, a
build chain and a second language.

## Decision

- hsx renders the HTML from S-expressions, and ningle-fbr routes the pages by
  their file path.
- Tailwind styles it, from its standalone binary, with no Node.
- The JavaScript is written by hand in `assets/js/`, beside the libraries it
  uses, and is served as it is written.

## Consequences

One language on the server, one process, and no build step but the stylesheet.
A page is a function, so a screen can be changed from the REPL of a running
server.

Anything genuinely interactive costs hand-written JavaScript, which is the
pressure that keeps the UI plain.
