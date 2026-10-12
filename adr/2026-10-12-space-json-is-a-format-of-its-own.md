# space.json is a format of its own

*2026-10-12, restating a decision of 2026-09-25*

## Context

A space's archive holds a `space.json` with its schema, contents, media and
keys. The delivery API also answers with contents and media as JSON, and the
two could be taken for one format.

## Decision

- `space.json` is koya's format for moving a space, not an answer to a request,
  and is not made by `web/presenters`.
- `usecases/archive` builds the document it holds and checks the one an import
  reads, as Lisp data. The archive's port in `infra/` converts that document to
  and from JSON, as
  [every edge does](2026-10-12-json-is-converted-at-the-edges.md).

## Consequences

- The archive has its own shape for contents and media, apart from what the
  delivery API serves, and one can change without the other.
- Reading an archive back is checked where the rest of an import is decided.
