# What an answer cannot draw is a toast

*2026-11-27, restating a decision of 2026-10-02*

## Context

Nagi reads an answer whole before it swaps it. It swaps a refused answer too
when an element of the answer has its id on the page, and reports every failure
with `fetcherr`: the answer's status and text, and whether it was swapped.

An action answers with its real status, and a refusal with the toast or the
place on the page for the reason. A body limit refused before the action runs,
or an answer that never came, has nothing of the page to draw.

## Decision

`koya.js` listens for `fetcherr`, and puts what was not swapped -- the text of
an answer without an element of the page, or nothing for one that never came --
in the toast, as the layout's `toast-failed` draws it.

## Consequences

- An action answers with its real status, and nothing on the element that asks
  says what happens to a refusal.
- koya's own fetches (the import's pieces) read their answers themselves.
