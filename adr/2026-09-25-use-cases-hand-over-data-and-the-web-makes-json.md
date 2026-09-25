# Use cases hand over data, and the web makes the JSON

*2026-09-25*

## Context

`adr/2026-09-25-the-server-is-layered-and-depends-inward.md` left the delivery
shape in `usecases/contents/delivery`: `content->jobject` built the object the
delivery API serves, and webhooks carry the same one, so it was called koya's
own output format and kept where the webhook use case could reach it. With it
went `media->jobject` and the media URL, and the webhook use case built its
payload's JSON; a refused destructive deploy carried its changes as JSON too.

That put the wire format in the use cases. Two jobs were mixed in
`content->jobject`: finding what a content points at -- the media of its media
fields, the contents a query's `include` names, whether they are published --
which is what koya does, and naming keys, writing nulls and making URLs
absolute, which is how an answer reads.

## Decision

- **A use case returns data.** `deliver` returns a `delivered`: the content, its
  model, and a copy of its data in which a media field holds its media and an
  included reference holds a `delivered`, or JSON null for one that is gone.
  The delivery API's reads return those; a refused deploy's details are the
  changes as core/diff makes them.
- **`web/presenters` makes the JSON**: `delivered->jobject` (with the system
  fields, the absolute URLs in richtext, the `fields` a query keeps),
  `media->jobject` and `media-url`, the admin API's content, a deploy's changes.
- **The webhook body goes through a port the web implements.**
  `ports/presenters` declares `webhook-payload`; the notifying use case hands it
  the event and the content before and after, delivered, and sends the string
  it gets. It is the one port that is not infra's: the shape is the delivery
  API's, and that is decided where the APIs are. The layer test lets the web
  depend on that port and on no other.
- **`space.json` stays with the archive use case.** It is koya's format for
  moving a space rather than an answer to a request, and reading it back is
  checking it, which is the use case's.

## Consequences

- What a use case returns reads the same whoever asks; how it looks on the wire
  can change in one place.
- The delivery API and webhooks still carry one shape, made by one function.
- Loading the web is what implements `ports/presenters`, so `web/app` loads
  `web/presenters` itself, and main's check for unimplemented ports covers it.
