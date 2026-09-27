# Reading content and managing it are two APIs

*2026-09-27, restating a decision of 2026-09-20*

## Context

Reading published content and managing it are different jobs with different
callers: a site's front end reads, a site's build and its author write.

## Decision

- The delivery API (`/api/v1`) is read-only and takes a delivery key.
- The admin API (`/admin/api`) manages the schema, contents, keys and media, and
  takes a management key or the owner's session.

## Consequences

The delivery API stays small enough to cache and to reimplement. A key that a
front end holds can read and nothing more.
