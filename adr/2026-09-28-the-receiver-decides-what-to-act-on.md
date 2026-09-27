# The receiver decides what to act on

*2026-09-28*

## Context

The docs told a hook that revalidates a site to return early on `draft`, and
then on `discard`. An event koya sends and tells every receiver to ignore is one
it need not send; what a receiver does with an event depends on the site, which
koya does not know.

## Decision

koya says what each event changes, and never which ones to act on or to ignore.
`draft` and `discard` change only a draft; `publish`, `unpublish` and `delete`
change what the delivery API serves. An example receiver checks the webhook
secret and does not filter events.

## Consequences

A receiver that should not act on a change to a draft has to say so itself, and
one that follows drafts, such as a preview, hears every change to them.
