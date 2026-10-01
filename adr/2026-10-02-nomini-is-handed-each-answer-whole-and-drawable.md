# Nomini is handed each answer whole, and drawable

*2026-10-02*

## Context

Nomini swaps what it has read of an answer whenever 20 ms pass without more, so
an answer that arrives in pieces is swapped in part. It draws nothing of an
answer that is not ok: it reports it with `fetcherr`, the body in the error's
message.

A refused answer could be drawn by each element's `fetcherr` handing the body
back to Nomini as a `data:` URL; that put a handler on every element that asks,
made a second request appear for each refusal, and depended on the wording of
Nomini's error. The actions could answer a refusal with 200; that would lose
what the status says to everything but the page.

## Decision

`koya.js` wraps `window.fetch`, and for a request Nomini makes (`nm-request`):

- reads the answer whole before Nomini sees it;
- hands it to Nomini as an ok answer whatever its status, so a refusal is drawn
  as any answer is;
- puts what has nothing to draw -- an answer that is not ok and has no element
  with an id, or one that never came -- in the toast, as the layout's
  `toast-failed` draws it.

koya's own fetches (an upload, the import's pieces) are made with the fetch
underneath, and read their answers themselves.

## Consequences

- An action answers with its real status, and nothing on the element that asks
  says what happens to a refusal.
- Nomini's `fetcherr` fires only for a request it cancels itself, which nothing
  listens for.
- koya depends on two things Nomini does without promising them: that it reads
  an answer through `window.fetch`, and how `$fetch` reads a `data:` URL. A new
  Nomini is checked against both before it is taken.
