# The logic of a site lives in the site, called by webhook

*2026-09-20*

## Context

Every CMS eventually grows hooks: run this when a post is published. Which means
a plugin system, a sandbox, and a way to deploy code into the CMS.

## Decision

koya has none of that. It enforces what the schema declares — types, required,
unique, patterns — and otherwise notifies: a change POSTs to the webhooks the
space declares, and the site does what it wants.

## Consequences

The server stays general: it has no idea what a blog is. Anything conditional
belongs to the site, which is already a program.

The cost is a round trip and the site having to be reachable, which for a build
that revalidates itself is the shape it was in anyway.
