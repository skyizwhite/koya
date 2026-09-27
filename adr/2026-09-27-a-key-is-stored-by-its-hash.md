# A key is stored by its hash, and its plaintext is shown once

*2026-09-27*

## Context

Delivery and management keys grant access to a space. A store that kept them in
plain text would hand every key to whoever read the database, a backup or an
exported archive.

## Decision

- A key is stored only as its SHA-256 hash. A request's key is hashed and looked
  up by that hash.
- The plaintext is shown once, in the answer that made the key, and never again.
- The store is handed the hash and never sees the plaintext.

## Consequences

- A lost key cannot be recovered; it is replaced.
- The database, a backup and an archive hold no key that can be used.
