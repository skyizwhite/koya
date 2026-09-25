# Woo holds a request body to the body limit

*2026-09-25*

## Context

Woo reads a whole request body before any middleware sees it, spilling it to a
file past a megabyte, up to smart-buffer's disk limit. With that limit left at
its gigabyte, anyone, signed in or not, could have Woo write up to a gigabyte
to the disk for each request to any path, however little koya takes:
`+max-body-bytes+`, 21 MB.

`adr/2026-09-25-a-space-has-no-size-limit-and-moves-in-pieces.md` kept the
gigabyte because past the limit Woo signaled an error it did not catch and
stopped serving. Woo now answers 413 there instead, refuses a body whose
Content-Length is past the limit before reading it, and deletes a body's file
itself.

## Decision

- **smart-buffer's disk limit is `+max-body-bytes+`**, set where the app is
  built.
- **A body over it is Woo's to refuse.** Woo answers it with 413 and a
  plain-text body, not koya's `too_large` error object; API.md and
  openapi.yaml say so. `*body-limit-middleware*` stays for Hunchentoot, which
  reaches the app before reading a body.

## Consequences

- A request body anyone sends is held to 21 MB on the disk, where it was 1 GB.
- A client cannot read an oversized body's 413 as JSON; the status is all it
  gets. In the admin UI, the answer to an upload over 21 MB is that text.
- It needs a Woo that answers 413 past the limit: with one that does not, any
  request of 21 MB stops the server.
