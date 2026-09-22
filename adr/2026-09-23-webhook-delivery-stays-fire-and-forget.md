# Webhook delivery stays fire-and-forget

*2026-09-23*

## Context

`notify-webhooks` raises a thread per notification and does not retry, so an
import of a hundred contents knocks on the receiver's door a hundred times at
once, and a receiver that is briefly down loses the call.

A queue with one worker, a bounded backoff, one log row per attempt and a stored
payload for redelivery was written, and then weighed against what koya is.

## Decision

None of it. The delivery path stays as it is.

Retries and redelivery exist for a receiver that was briefly down, and the
recovery for that already costs no code: publish the content again, which fires
the webhook again. The thread per notification only bites on a bulk import,
which happens once at migration time — and pacing an import is the import
script's job, not the server's.

## Consequences

A hut does not need an asynchronous delivery service. What is kept is the log:
what each call answered is in `webhook_deliveries` and on the space's webhook
page, so a failure is visible even though nothing acts on it.

Worth revisiting if the shape of the problem changes: several receivers that
cannot be reconciled by republishing, or delete events that matter enough to
chase.
