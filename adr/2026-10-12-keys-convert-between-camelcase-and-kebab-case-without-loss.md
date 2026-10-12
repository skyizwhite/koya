# Keys convert between camelCase and kebab-case without loss

*2026-10-12*

## Context

JSON keys are camelCase, and Lisp data has kebab-case keywords: the SDK's client
converts between them, and so does every edge once
[JSON stays at the edges](2026-10-12-json-is-converted-at-the-edges.md). A
field name may be any of `^[a-z][a-zA-Z0-9]*`. Converting by words, as the
`kebab` library does, loses names: `pageURL` and `pageUrl` both become
`:page-url`, which comes back as `pageUrl`, and `item2Name` comes back as
`item2name`. A field would then be written back under a name it does not have,
and two fields would share a key.

## Decision

- camelCase becomes kebab-case by putting `-` and the lowercase letter in place
  of each uppercase one: `eventAt` is `:event-at`, `pageURL` is `:page-u-r-l`,
  `item2Name` is `:item2-name`.
- kebab-case becomes camelCase by the reverse: each `-` and the letter after it
  become that letter in uppercase.
- One conversion, in `koya-core`, is used by the server's edges and the SDK.

## Consequences

- Every field name comes back as it was, and two names never share a keyword.
- A name with uppercase letters in a row has a keyword that reads letter by
  letter, `:page-u-r-l`.
- A site using the SDK that reads a field such as `pageURL` finds it under
  `:page-u-r-l` where it was `:page-url`.
