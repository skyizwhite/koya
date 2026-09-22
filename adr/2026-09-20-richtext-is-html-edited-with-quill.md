# Rich text is HTML, edited with Quill

*2026-09-20*

## Context

Rich text was first Markdown, converted to HTML on the way out by 3bmd, to avoid
bringing a JavaScript editor into the admin UI. Writing in a textarea and
guessing at the result turned out to be the worse trade, and content arriving
from elsewhere is HTML already.

## Decision

A `:richtext` field holds HTML and is edited with Quill. The HTML is written
into a hidden input when the form is submitted, and stored as it is. Markdown
and 3bmd are gone.

## Consequences

What is stored is what is delivered: no renderer between them, and no
re-rendering when a renderer changes. Imported HTML survives.

Quill is a dependency in the page, and its quirks are the admin UI's problem —
it collapses ideographic spaces on paste and turns spaces into `&nbsp;` on the
way out, both worked around in `koya-editor.js`.
