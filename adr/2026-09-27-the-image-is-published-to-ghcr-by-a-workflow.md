# The image is published to GHCR by a workflow

*2026-09-27, restating a decision of 2026-09-23*

## Context

Someone who runs koya should not have to build it. An image built from the
repository's Dockerfile by hand is also an image nobody checked.

## Decision

- The `image` workflow publishes `ghcr.io/skyizwhite/koya`. A `v*` tag gives
  `X.Y.Z`, `X.Y` and `latest`, and `master` gives `edge`.
- `linux/amd64` and `linux/arm64` are each built on a runner of that
  architecture, not under emulation.
- Each one is started and asked for `/health` before anything is pushed.

## Consequences

- koya is run by pulling an image, and a release is a tag.
- An image that does not start is never published.
