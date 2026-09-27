# Every admin UI page links to its source

*2026-09-27, restating a decision of 2026-09-23*

## Context

The AGPL asks a server that others use over the network to offer them its
source. koya's admin UI is what those users see.

## Decision

- Every admin UI page, the login page included, ends with a footer naming the
  version, linking to the source and stating the licence.
- The link is read from the `:homepage` of `koya-server.asd`.

## Consequences

A fork that changes the `:homepage` offers its own source rather than this
repository's, without touching the footer.
