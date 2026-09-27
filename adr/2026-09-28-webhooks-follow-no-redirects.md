# Webhooks follow no redirects

*2026-09-28*

## Context

Where a webhook is sent is checked on its URL's host, and every call carries
the space's webhook secret. A followed redirect would reach a host that was
never checked, and hand it the secret.

## Decision

A webhook call does not follow a redirect. A 3xx answer is logged as the
answer, and counts as a refusal.

## Consequences

- The host that was checked is the only one a call reaches, and the secret goes
  nowhere else.
- A receiver that moved is seen in the log as a 3xx, and the schema's URL is
  what is changed.
