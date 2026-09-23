# The server listens on 3100

*2026-09-23*

## Context

`KOYA_PORT` defaulted to 3000, the port the image exposed too. 3000 is also the
default of most of what a koya site is built with — Next.js, Nuxt, Remix,
Express, Rails — so a site and its CMS running on one machine, in local
development or in one compose file, both want it.

## Decision

3100: the default of `KOYA_PORT`, the port the image exposes and the one every
example uses. It sits next to the site's 3000 without meeting it.

## Consequences

A deployment that relied on the old default — a platform told to send traffic
to 3000 — has to be pointed at 3100, or set `KOYA_PORT=3000`. A local `.env`
that names its port is unaffected.
