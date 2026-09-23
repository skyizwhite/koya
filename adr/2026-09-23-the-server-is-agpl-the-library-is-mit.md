# The server is AGPL, the library is MIT

*2026-09-23*

## Context

koya was MIT throughout. It is a server that others reach over the network, and
under MIT anyone may run a modified copy as a service without giving the changes
back. The AGPL exists for that case.

koya is also a library: a site loads the `koya` system into its own code to
declare its schema and read its content. Under the AGPL, that site could be read
as a work based on koya, and one served over the network would owe its own
source. For a headless CMS that would be a reason not to use it.

Every commit so far is by one author, so the licence can still be changed
without asking anyone.

## Decision

Two licences, split along the two ASDF systems:

- `koya-server` — the server, its admin UI and assets, and everything in the
  repository not listed below — is under the AGPL v3.0 or later (`LICENSE`).
- `koya` — `koya.asd`, `src/main.lisp`, `src/client.lisp`, `src/config.lisp`,
  `src/core.lisp` and `src/core/` — stays under MIT (`LICENSE-MIT`).

The server uses the library's core; MIT code may be part of an AGPL work, so the
split needs nothing more. A site talks to the server over HTTP, which the AGPL
does not reach.

Every admin UI page, the login page included, ends with a footer naming the
version, linking to the source and stating the licence. The link is read from
the `:homepage` of `koya-server.asd`, so a fork that changes it offers its own
source rather than this repository's.

## Consequences

Versions released before this change stay available under MIT.

Outside contributions from here on come under the licence of the part they
touch. Moving a file from the library into the server, or the other way, is a
licensing change as well as a code change: a file moved into `src/server/`
becomes AGPL, and code the library takes from the server needs the author's
consent to become MIT.
