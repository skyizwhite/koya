# An id koya makes for anything but a content is a ULID

Superseded by adr/2026-10-13-an-id-koya-makes-for-a-key-a-deploy-a-delivery-or-an-archive-is-a-ulid.md

*2026-10-10, restating a decision of 2026-09-27*

## Context

Media, keys, deploys, webhook deliveries and archives need ids, made by koya
itself.

## Decision

Every id koya makes for them is a ULID, from `koya-core/ulid`. A content's id is
[made otherwise](2026-10-10-a-content-id-koya-makes-is-twelve-letters-and-digits.md).

## Consequences

An id is made without asking the database, and ids sort in the order they were
made, which the deploy and webhook logs rely on to list the newest first.
