# Two REST APIs, JSON only

Superseded by adr/2026-09-27-delivery-and-admin-are-two-apis.md
Superseded by adr/2026-09-27-the-apis-are-rest-and-json-only.md
Superseded by adr/2026-09-27-json-keys-are-camelcase.md
Superseded by adr/2026-09-27-admin-routes-name-the-resource-before-the-space.md
Superseded by adr/2026-09-27-a-reference-is-embedded-only-when-include-names-it.md

*2026-09-20*

## Context

Reading published content and managing it are different jobs with different
callers: a site's front end reads, a site's build and its author write.

## Decision

Two APIs. The delivery API (`/api/v1`) is read-only and takes a delivery key;
the admin API (`/admin/api`) manages the schema, contents, keys and media and
takes a management key. REST and JSON only — no GraphQL until something needs
it.

JSON keys are camelCase; the Lisp client converts them to kebab-case keywords.
The schema document and both APIs are specified in `docs/`, not only implemented.

Admin routes are `/admin/api/<resource>/<space>/…` rather than
`/admin/api/<space>/<resource>`, so a space can never be named `schema`.

References are returned as ids and embedded only when `include` names them —
`include=tags,author.avatar` — rather than by a `depth` number that expands
whatever happens to be there.

## Consequences

The delivery API stays small enough to cache and to reimplement. A site that
wants a reference embedded says which one, so nothing is fetched by accident.
