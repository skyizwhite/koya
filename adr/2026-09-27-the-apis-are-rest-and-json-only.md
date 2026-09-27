# The APIs are REST and JSON only

*2026-09-27, restating a decision of 2026-09-20*

## Context

A CMS API can be REST, GraphQL or both. Each style the server speaks is another
one to specify, test and keep in step with the others.

## Decision

Both APIs are REST and speak JSON only. There is no GraphQL until something
needs it.

## Consequences

A site reads koya with plain HTTP, and one specification describes each API.
