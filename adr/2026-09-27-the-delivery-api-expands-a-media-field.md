# The delivery API always expands a media field

*2026-09-27, restating a decision of 2026-09-20*

## Context

A `:media` field holds an image's id. A site cannot draw an image from its id
alone.

## Decision

The delivery API always answers a `:media` field with the image's object, its
URL included, without being asked. A reference field is expanded only on
request; a media field is not, because there is nothing to choose.

## Consequences

- A site never makes a second request to find where an image is.
- The expansion cannot nest: an image refers to nothing, so there is no depth to
  limit.
