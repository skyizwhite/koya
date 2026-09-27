# Keys and the webhook secret move with a space

*2026-09-27, restating a decision of 2026-09-23*

## Context

A site's `.env` holds its delivery and management keys, and its webhook
receiver checks the webhook secret. A moved space whose keys changed would break
the site.

## Decision

- Keys travel as they are stored, as SHA-256, so the archive holds no key that
  can be used.
- The webhook secret is stored in plain text, because it is sent with every
  call, and it travels in plain text.

## Consequences

- The site keeps working against the new instance, with nothing about its keys
  or secret changed.
- With the secret and every draft in it, an archive is to be kept as privately
  as the database.
- A development instance seeded from production sends to production's webhooks.
  Point them elsewhere with a deploy if that matters.
