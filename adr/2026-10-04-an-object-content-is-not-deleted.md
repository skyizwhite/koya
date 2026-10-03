# An object content is not deleted

*2026-10-04*

## Context

The admin UI offered **Delete** on an object model's content, documented as
starting the content over. It removed the content with its whole history, sent
`delete`, and left the delivery API answering `404` until someone wrote it
again. An object model's content is not one of many that come and go: the site
reads it as part of the model.

## Decision

An object model's content is not deleted. It goes only with its model — when
the model is removed, or its kind changed, by a deploy. Deleting it is refused
with `409 object_stays`, and the admin UI has no **Delete** for it.

## Consequences

- Taking it off the site is **Unpublish**, which keeps its data and history.
- Starting it over is writing it again; its history keeps what it was.
- The admin UI's **Danger zone** shows for an object content only while it is
  published, with **Unpublish** alone.
