# An id koya makes for a key, a deploy, a delivery or an archive is a ULID

*2026-10-13, restating a decision of 2026-10-10*

## Context

Keys, deploys, webhook deliveries and archives need ids, made by koya itself.
Unlike a content's or a media's id, these are not where a site's readers see
them.

## Decision

Every id koya makes for them is a ULID, from `koya-core/ulid`. A content's and a
media's id are
[made otherwise](2026-10-13-an-id-koya-makes-for-a-content-or-a-media-is-twelve-letters-and-digits.md).

## Consequences

An id is made without asking the database, and ids sort in the order they were
made, which the deploy and webhook logs rely on to list the newest first.
