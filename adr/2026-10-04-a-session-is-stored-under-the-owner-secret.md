# A session is stored under the owner secret

*2026-10-04*

## Context

A session row was keyed by the session id itself, so the database, and any
backup of `/data`, held every live login. Nothing ended a session when the owner
replaced `KOYA_SECRET`, the moment they most want everyone else out. Keeping a
hash of the secret to notice the change would put something to guess the secret
from into the same backup.

## Decision

A session row is keyed by the HMAC-SHA256 of the session id under the owner
secret. The id is in the cookie only; the store computes the key for every read
and write.

## Consequences

- The database and its backups hold no session anyone can use.
- A server started with another secret finds none of the rows it had: every
  session ends, with nothing to compare and nothing stored about the secret.
  The old rows are swept with the expired ones.
- Changing how the key is made ends every session once, which is what this
  change itself does.
