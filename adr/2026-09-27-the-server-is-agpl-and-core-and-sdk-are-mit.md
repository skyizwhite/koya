# The server is AGPL, and the core and the SDK are MIT

*2026-09-27, restating a decision of 2026-09-23*

## Context

koya is a server that others reach over the network. Under MIT anyone may run a
modified copy as a service without giving the changes back. The AGPL exists for
that case.

koya is also a library: a site loads `koya-sdk` into its own code to declare its
schema and read its content. Under the AGPL, that site could be read as a work
based on koya, and one served over the network would owe its own source. For a
headless CMS that would be a reason not to use it.

koya had one author when this was decided, so the licence could be changed
without asking anyone.

## Decision

Two licences, split along the ASDF systems:

- `koya-core` and `koya-sdk` are MIT (`LICENSE-MIT`): `koya-core.asd`,
  `koya-sdk.asd`, `src/core/` and `src/sdk/`.
- `koya-server`, and everything else in the repository, is under the AGPL v3.0
  or later (`LICENSE`).

The server uses `koya-core`. MIT code may be part of an AGPL work, so the split
needs nothing more. A site talks to the server over HTTP, which the AGPL does
not reach.

## Consequences

- Versions released before 2026-09-23 stay available under MIT.
- Outside contributions come under the licence of the part they touch.
- Moving a file across the line is a licensing change as well as a code change.
  A file moved into `src/server/` becomes AGPL, and code the core or the SDK
  takes from the server needs the author's consent to become MIT.
