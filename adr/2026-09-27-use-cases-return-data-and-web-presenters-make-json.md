# Use cases return data, and web/presenters makes the JSON

*2026-09-27, restating a decision of 2026-09-25*

## Context

Delivering a content does two jobs. One is finding what it points at: the media
of its media fields, the contents a query's `include` names, and whether they
are published. That is what koya does. The other is naming keys, writing nulls
and making URLs absolute, which is how an answer reads. Kept together in a use
case, they put the wire format in the use cases.

## Decision

- **A use case returns data.** `deliver` in `usecases/delivery` returns a
  `delivered`: the content, its model, and a copy of its data in which a media
  field holds its media and an included reference holds a `delivered`, or JSON
  null for one that is gone. A refused deploy's details are the changes as
  `koya-core/diff` makes them.
- **`web/presenters` makes the JSON**: `delivered->jobject` (with the system
  fields, the absolute URLs in richtext, and the `fields` a query keeps),
  `media->jobject` and `media-url`, `admin-content->jobject` for the admin API,
  and `changes->jarray` for a deploy's changes.

## Consequences

- What a use case returns reads the same whoever asks, and how it looks on the
  wire can change in one place.
- The delivery API and webhooks carry one shape, made by one function.
