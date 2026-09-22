# Webhooks belong to the space and get every event

*2026-09-22*

## Context

Webhooks were declared in two places — on the space and on each model — and each
one listed the events it wanted. Reading "what fires where" meant reading the
whole schema, and a hook wanting everything had to say so.

## Decision

Every webhook is the space's, declared together in `defwebhooks`. `:only`
narrows one to a model or a list of them; without it, it covers every model,
including models added later.

There is nothing to subscribe to: every webhook is sent every event — publish,
unpublish, delete, draft — and the payload's `event` says which. The receiver
decides what to act on.

The secret is the space's, sent as `X-KOYA-WEBHOOK-KEY`, shown and rotated on
the keys page.

## Consequences

Which hook goes where is one list. A receiver must look at `event`, which a
revalidation hook wants to do anyway to ignore drafts.

Per-webhook secrets were considered when several receivers each learn a token
good for the others; with one site and one receiver there is nothing to separate.
