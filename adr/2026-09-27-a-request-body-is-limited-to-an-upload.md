# A request body is limited to the largest upload and a megabyte

*2026-09-27, restating a decision of 2026-09-20*

## Context

The server is on the public internet, and anyone, signed in or not, can send it
a request with a body. Without a limit, a body is held however large it is.

## Decision

A request body is limited to `+max-body-bytes+`: the largest media upload, 20 MB,
and one megabyte more for the rest of the form. The limit holds for every path.

## Consequences

- An upload of the largest size still fits with its form.
- A body over the limit is refused with 413 before any route sees it.
