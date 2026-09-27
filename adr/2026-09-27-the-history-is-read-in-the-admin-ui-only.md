# A content's history is read in the admin UI only

*2026-09-27, restating a decision of 2026-09-23*

## Context

The revisions of a content are there to answer an editor's questions: what
changed, when, and who changed it.

## Decision

The history is read at `/s/{space}/m/{model}/{id}/history`, in two views:

- the published versions only, each compared with the one published before it;
- every revision, each compared with the one before it.

The delivery API and the admin API do not read it.

## Consequences

A site sees only what is published or drafted now. What an old version held is
a question for the admin UI, and neither API has to promise a shape for it.
