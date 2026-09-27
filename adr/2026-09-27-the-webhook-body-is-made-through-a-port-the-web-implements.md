# The webhook body is made through a port the web implements

*2026-09-27, restating a decision of 2026-09-25*

## Context

A webhook carries a content in the delivery API's shape, and that shape is made
in `web/presenters`
([adr/2026-09-27-use-cases-return-data-and-web-presenters-make-json.md](2026-09-27-use-cases-return-data-and-web-presenters-make-json.md)).
The use case that sends webhooks cannot depend on the web.

## Decision

- `usecases/ports/presenters` declares `webhook-payload`. The notifying use case
  in `usecases/webhooks` hands it the space, the model, the id, the event and
  the content before and after, delivered, and sends the string it gets.
- `web/presenters` implements it. It is the one port that is not infra's: the
  shape is the delivery API's, and that is decided where the APIs are.
- The layers spec lets the web depend on that port and on no other.

## Consequences

- Loading the web is what implements the port, so `web/app` loads
  `web/presenters` itself, and main's check for unimplemented ports covers it.
