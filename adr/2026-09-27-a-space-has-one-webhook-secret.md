# A space has one webhook secret for all its webhooks

*2026-09-27, restating a decision of 2026-09-22*

## Context

A receiver needs to know that a webhook came from koya. Each webhook could have
its own secret, or the space could have one.

## Decision

- The secret is the space's, sent with every webhook as `X-KOYA-WEBHOOK-KEY`.
- It is shown and rotated on the space's keys page.

## Consequences

- Every receiver of a space learns a token that is good for the others.
  Per-webhook secrets would separate them, but with one site and one receiver
  there is nothing to separate.
