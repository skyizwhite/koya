# A key is made in the domain, and the store is handed its hash

Superseded by adr/2026-09-27-a-key-is-stored-by-its-hash.md
Superseded by adr/2026-09-27-a-key-says-what-kind-it-is.md

*2026-09-27*

## Context

`adr/2026-09-25-the-store-saves-what-a-use-case-decided.md` said a port keeps
what it is given and decides nothing, and that what the store still decided
would move out as it was touched. Keys had not moved. `create-delivery-key`
and `create-management-key` in `infra/db/` drew the plaintext, chose its
`koya_` / `koya_mgmt_` prefix, hashed it and made its id; `space-for-*-key`
hashed what a request carried before looking it up. `insert-space` and
`rotate-webhook-secret` drew the webhook secret in `infra/db/schema-store`.
`usecases/keys` only re-exported the port.

So what a key is -- how long, which prefix, which hash -- was infra's, and
`infra/db/management-keys` imported `hash-key` from `infra/db/delivery-keys`,
the one place two table modules depended on each other. A content's draft key
was already drawn in the domain (`new-draft-key`), so the two kinds of secret
were made in two layers.

## Decision

- **`domain/key` makes and hashes keys**: `new-delivery-key`,
  `new-management-key`, `hash-key` and `new-webhook-secret`.
- **`usecases/keys` creates, checks and rotates them.** `create-*-key` makes
  the plaintext, its id and time, and hands the store the hash;
  `space-for-*-key` and `management-key-label` hash what they are given and ask
  the store by the hash; `rotate-webhook-secret` draws a secret and sets it.
  Their lambda lists stay as they were, so the web does not change.
- **The key port speaks hashes only.** `insert-*-key (space &key id hash label
  created-at)` stores a new key and an imported one alike (it was
  `import-*-key`); `space-by-delivery-key-hash`, `space-by-management-key-hash`
  and `label-by-management-key-hash` look one up. `insert-space` takes the
  webhook secret, and `rotate-webhook-secret` is no longer a port.

## Consequences

- The store never sees a plaintext key.
- A key's format can be read and changed in one file, and tested without a
  database.
- The infra key modules depend only on `infra/db/connection` and the port.
- Ids and creation times of media, deploys and webhook deliveries are still
  made in `infra/`. They decide nothing a reader would ask about, and move
  when those modules are next touched for another reason.
