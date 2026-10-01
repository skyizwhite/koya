# Hand-written JavaScript has no comments

*2026-10-02*

## Context

`assets/js/koya.js` carried about a hundred lines of comments: what each
factory holds, why a Quill quirk is worked around, how Nomini is reached. They
had the trouble `src/` had before
([src has no comments or docstrings](2026-09-27-src-has-no-comments-or-docstrings.md)):
they changed with the code or went stale, and nothing told which.

## Decision

- The JavaScript koya writes, `assets/js/koya.js`, has no comments.
- A reason the code cannot carry is an ADR, as it is for `src/`.
- The libraries beside it (`nomini.js`, `quill.min.js`, `qrcode.min.js`) are
  kept as they are published, their headers included.

## Consequences

- Why a line of `koya.js` is there is found in the commit that wrote it.
- What the browser must keep doing has no spec to hold it, so a change to
  `koya.js` is checked in a browser before it is taken.
