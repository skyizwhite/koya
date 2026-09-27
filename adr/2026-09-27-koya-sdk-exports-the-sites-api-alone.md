# koya-sdk exports the site's API alone

*2026-09-27*

## Context

The `koya-sdk` package re-exported all of `koya-core`, `koya-sdk/config` and
`koya-sdk/client`: 125 symbols. Only 44 of them are what a site uses, the ones in
`docs/lisp-sdk.md`. The rest were exported for the server or for a spec, and a
site could not tell the two apart.

## Decision

- The `koya-sdk` package names the 44 symbols of the site's API, imports each one
  from the package that defines it, and exports nothing else.
- There is no second facade for the spec. The spec imports what it needs from
  the package that defines it.
- `koya-spec/sdk/main` holds the package to that list.

## Consequences

A site that used a `koya-core` symbol through `koya-sdk:` has to import it from
`koya-core` now.
